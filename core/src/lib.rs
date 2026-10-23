//! Independent Mac gesture state machine. No OS hooks, threads, timers or I/O.
use serde::{Deserialize, Serialize};
use std::{
    collections::HashSet,
    ffi::{c_char, CStr, CString},
};

pub const MARKER: i64 = 0x474c_4954_455f_3031;
pub fn is_own(marker: i64) -> bool {
    marker == MARKER || marker == i64::from(MARKER as u32)
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Config {
    pub schema: u32,
    pub enabled: bool,
    pub distance: f64,
    pub dominance: f64,
    pub bindings: Vec<Binding>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
pub struct Binding {
    pub trigger: String,
    pub tap_passthrough: bool,
    pub click_action: Option<String>,
    pub left: Option<String>,
    pub right: Option<String>,
    pub up: Option<String>,
    pub down: Option<String>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Trigger {
    Mouse(u32),
    Key(u32),
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Chord {
    pub code: u32,
    pub flags: u64,
}

fn key(value: &str) -> Option<u32> {
    Some(match value {
        "A" => 0,
        "S" => 1,
        "D" => 2,
        "F" => 3,
        "H" => 4,
        "G" => 5,
        "Z" => 6,
        "X" => 7,
        "C" => 8,
        "V" => 9,
        "B" => 11,
        "Q" => 12,
        "W" => 13,
        "E" => 14,
        "R" => 15,
        "Y" => 16,
        "T" => 17,
        "1" => 18,
        "2" => 19,
        "3" => 20,
        "4" => 21,
        "6" => 22,
        "5" => 23,
        "EQUALS" => 24,
        "9" => 25,
        "7" => 26,
        "MINUS" => 27,
        "8" => 28,
        "0" => 29,
        "]" => 30,
        "O" => 31,
        "U" => 32,
        "[" => 33,
        "I" => 34,
        "P" => 35,
        "ENTER" | "RETURN" => 36,
        "L" => 37,
        "J" => 38,
        "QUOTE" => 39,
        "K" => 40,
        "SEMICOLON" => 41,
        "BACKSLASH" => 42,
        "COMMA" => 43,
        "SLASH" => 44,
        "N" => 45,
        "M" => 46,
        "PERIOD" => 47,
        "TAB" => 48,
        "SPACE" => 49,
        "BACKTICK" => 50,
        "BACKSPACE" => 51,
        "ESC" | "ESCAPE" => 53,
        "DELETE" => 117,
        "LEFT" => 123,
        "RIGHT" => 124,
        "DOWN" => 125,
        "UP" => 126,
        "HOME" => 115,
        "END" => 119,
        "PAGEUP" => 116,
        "PAGEDOWN" => 121,
        "F1" => 122,
        "F2" => 120,
        "F3" => 99,
        "F4" => 118,
        "F5" => 96,
        "F6" => 97,
        "F7" => 98,
        "F8" => 100,
        "F9" => 101,
        "F10" => 109,
        "F11" => 103,
        "F12" => 111,
        "F13" => 105,
        "F14" => 107,
        "F15" => 113,
        "F16" => 106,
        "F17" => 64,
        "F18" => 79,
        "F19" => 80,
        "F20" => 90,
        _ => return None,
    })
}
pub fn parse_chord(text: &str) -> Result<Chord, String> {
    let parts: Vec<_> = text
        .split('+')
        .map(|s| s.trim().to_ascii_uppercase())
        .collect();
    if parts.is_empty() || parts.len() > 5 {
        return Err("Use up to four modifiers and one key".into());
    }
    let mut flags = 0u64;
    for modifier in &parts[..parts.len() - 1] {
        let bit = match modifier.as_str() {
            "CMD" | "COMMAND" => 1 << 20,
            "CTRL" | "CONTROL" => 1 << 18,
            "OPT" | "OPTION" | "ALT" => 1 << 19,
            "SHIFT" => 1 << 17,
            _ => return Err(format!("Unknown modifier: {modifier}")),
        };
        if flags & bit != 0 {
            return Err("Use each modifier only once".into());
        }
        flags |= bit;
    }
    let target = &parts[parts.len() - 1];
    Ok(Chord {
        code: key(target).ok_or_else(|| format!("Unknown target key: {target}"))?,
        flags,
    })
}
pub fn parse_trigger(text: &str) -> Result<Trigger, String> {
    let upper = text.trim().to_ascii_uppercase();
    if let Some(number) = upper.strip_prefix("MOUSE") {
        let n = number
            .parse::<u32>()
            .map_err(|_| "Use Mouse3 through Mouse32")?;
        if (3..=32).contains(&n) {
            return Ok(Trigger::Mouse(n - 1));
        }
    } else if let Some(number) = upper.strip_prefix('F') {
        if number.parse::<u32>().is_ok_and(|n| (13..=20).contains(&n)) {
            if let Some(code) = key(&upper) {
                return Ok(Trigger::Key(code));
            }
        }
    }
    Err("Triggers support Mouse3 through Mouse32 and F13 through F20".into())
}
#[derive(Clone, Copy, Debug, Default)]
enum Hold {
    #[default]
    Idle,
    Armed(f64, f64),
    Consumed,
}
struct CompiledBinding {
    trigger: Trigger,
    passthrough: bool,
    click: Option<Chord>,
    actions: [Option<Chord>; 4],
    hold: Hold,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Outcome {
    pub suppress: u32,
    /// 0=no action, 1=shortcut, 2=mouse tap, 3=keyboard tap.
    pub kind: u32,
    pub code: u32,
    pub flags: u64,
}
impl Outcome {
    fn chord(chord: Chord, suppress: bool) -> Self {
        Self {
            suppress: u32::from(suppress),
            kind: 1,
            code: chord.code,
            flags: chord.flags,
        }
    }
}
pub struct Engine {
    enabled: bool,
    distance: f64,
    dominance: f64,
    bindings: Vec<CompiledBinding>,
    draining: HashSet<Trigger>,
    error: CString,
}
impl Default for Engine {
    fn default() -> Self {
        Self {
            enabled: false,
            distance: 360.,
            dominance: 1.25,
            bindings: vec![],
            draining: HashSet::new(),
            error: CString::default(),
        }
    }
}
impl Engine {
    pub fn configure(&mut self, config: Config) -> Result<(), String> {
        if config.schema != 1 {
            return Err("Unsupported configuration schema".into());
        }
        if !config.distance.is_finite() || !(1. ..=4000.).contains(&config.distance) {
            return Err("Distance must be 1–4000 points".into());
        }
        if !config.dominance.is_finite() || !(1.01..=10.).contains(&config.dominance) {
            return Err("Dominance must be 1.01–10".into());
        }
        if config.bindings.len() > 32 {
            return Err("At most 32 triggers".into());
        }
        let mut compiled: Vec<CompiledBinding> = vec![];
        for binding in config.bindings {
            let trigger = parse_trigger(&binding.trigger)?;
            if compiled.iter().any(|b| b.trigger == trigger) {
                return Err(format!("Duplicate trigger: {}", binding.trigger));
            }
            let parse = |text: Option<String>| text.as_deref().map(parse_chord).transpose();
            compiled.push(CompiledBinding {
                trigger,
                passthrough: binding.tap_passthrough,
                click: parse(binding.click_action)?,
                actions: [
                    parse(binding.left)?,
                    parse(binding.right)?,
                    parse(binding.up)?,
                    parse(binding.down)?,
                ],
                hold: Hold::Idle,
            });
        }
        // Validate first; an invalid draft must not alter the active engine.
        self.cancel();
        self.bindings = compiled;
        self.distance = config.distance;
        self.dominance = config.dominance;
        self.enabled = config.enabled;
        Ok(())
    }
    pub fn cancel(&mut self) {
        for b in &mut self.bindings {
            if !matches!(b.hold, Hold::Idle) {
                self.draining.insert(b.trigger);
            }
            b.hold = Hold::Idle;
        }
    }
    pub fn disable(&mut self) {
        self.cancel();
        self.enabled = false;
    }
    /// Events: 1=mouse down, 2=mouse up, 3=motion, 4=key down, 5=key up.
    pub fn process(&mut self, event: u32, code: u32, x: f64, y: f64) -> Outcome {
        if !x.is_finite() || !y.is_finite() {
            return Outcome::default();
        }
        if event == 3 {
            if !self.enabled {
                return Outcome::default();
            }
            // Each input event can complete more than one held binding; return the first
            // action only, and consume all qualifying holds to avoid delayed firing.
            let mut result = Outcome::default();
            for b in &mut self.bindings {
                if let Hold::Armed(sx, sy) = b.hold {
                    let (dx, dy) = (x - sx, y - sy);
                    let (ax, ay) = (dx.abs(), dy.abs());
                    let direction = if ax >= self.distance && ax >= ay * self.dominance {
                        Some(usize::from(dx >= 0.))
                    } else if ay >= self.distance && ay >= ax * self.dominance {
                        Some(if dy < 0. { 2 } else { 3 })
                    } else {
                        None
                    };
                    if let Some(d) = direction {
                        b.hold = Hold::Consumed;
                        if result.kind == 0 {
                            if let Some(c) = b.actions[d] {
                                result = Outcome::chord(c, false);
                            }
                        }
                    }
                }
            }
            return result;
        }
        let trigger = match event {
            1 | 2 => Trigger::Mouse(code),
            4 | 5 => Trigger::Key(code),
            _ => return Outcome::default(),
        };
        let down = matches!(event, 1 | 4);
        if self.draining.contains(&trigger) {
            if !down {
                self.draining.remove(&trigger);
            }
            return Outcome {
                suppress: 1,
                ..Outcome::default()
            };
        }
        let Some(b) = self.bindings.iter_mut().find(|b| b.trigger == trigger) else {
            return Outcome::default();
        };
        if down {
            if !self.enabled {
                return Outcome::default();
            }
            if matches!(b.hold, Hold::Idle) {
                b.hold = Hold::Armed(x, y);
            }
            Outcome {
                suppress: 1,
                ..Outcome::default()
            }
        } else {
            let hold = std::mem::take(&mut b.hold);
            if matches!(hold, Hold::Idle) {
                return Outcome::default();
            }
            if matches!(hold, Hold::Armed(..)) {
                if let Some(c) = b.click {
                    return Outcome::chord(c, true);
                }
                if b.passthrough {
                    return Outcome {
                        suppress: 1,
                        kind: if matches!(trigger, Trigger::Mouse(_)) {
                            2
                        } else {
                            3
                        },
                        code,
                        flags: 0,
                    };
                }
            }
            Outcome {
                suppress: 1,
                ..Outcome::default()
            }
        }
    }
}

// All calls belong to the macOS main run loop. Pointers remain owned by this API.
#[no_mangle]
pub extern "C" fn gl_new() -> *mut Engine {
    Box::into_raw(Box::new(Engine::default()))
}
/// # Safety
/// `engine` must be null or a live handle from gl_new, released exactly once.
#[no_mangle]
pub unsafe extern "C" fn gl_free(engine: *mut Engine) {
    if !engine.is_null() {
        drop(unsafe { Box::from_raw(engine) });
    }
}
/// # Safety
/// Use a live engine and a valid, NUL-terminated UTF-8 JSON string; no concurrent calls.
#[no_mangle]
pub unsafe extern "C" fn gl_configure(engine: *mut Engine, json: *const c_char) -> u32 {
    let Some(e) = (unsafe { engine.as_mut() }) else {
        return 0;
    };
    if json.is_null() {
        return 0;
    }
    let result = (unsafe { CStr::from_ptr(json) })
        .to_str()
        .map_err(|e| e.to_string())
        .and_then(|s| {
            if s.len() > 65536 {
                Err("Configuration exceeds 64 KiB".into())
            } else {
                serde_json::from_str::<Config>(s).map_err(|e| e.to_string())
            }
        })
        .and_then(|c| e.configure(c));
    match result {
        Ok(()) => {
            e.error = CString::default();
            1
        }
        Err(error) => {
            e.error = CString::new(error.replace('\0', "?")).unwrap_or_default();
            0
        }
    }
}
/// # Safety
/// Use a live handle. The returned string is borrowed until the next configure/free.
#[no_mangle]
pub unsafe extern "C" fn gl_error(engine: *const Engine) -> *const c_char {
    unsafe { engine.as_ref() }.map_or(std::ptr::null(), |e| e.error.as_ptr())
}
/// # Safety
/// Use a live engine with serialized main-run-loop access.
#[no_mangle]
pub unsafe extern "C" fn gl_process(
    engine: *mut Engine,
    event: u32,
    code: u32,
    x: f64,
    y: f64,
) -> Outcome {
    unsafe { engine.as_mut() }.map_or_else(Outcome::default, |e| e.process(event, code, x, y))
}
/// # Safety
/// Use a live engine with serialized main-run-loop access.
#[no_mangle]
pub unsafe extern "C" fn gl_disable(engine: *mut Engine) {
    if let Some(e) = unsafe { engine.as_mut() } {
        e.disable();
    }
}
#[no_mangle]
pub extern "C" fn gl_is_own(marker: i64) -> u32 {
    u32::from(is_own(marker))
}
#[no_mangle]
pub extern "C" fn gl_marker() -> i64 {
    MARKER
}

#[cfg(test)]
mod tests;
