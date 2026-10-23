use super::*;
fn config() -> Config {
    serde_json::from_str(include_str!("../config.example.json")).unwrap()
}
fn engine() -> Engine {
    let mut e = Engine::default();
    let mut c = config();
    c.enabled = true;
    e.configure(c).unwrap();
    e
}
#[test]
fn defaults_disabled_and_valid() {
    let c = config();
    assert!(!c.enabled);
    assert_eq!(c.distance, 360.);
    Engine::default().configure(c).unwrap();
}
#[test]
fn once_per_hold_and_no_action_after_release() {
    let mut e = engine();
    assert_eq!(e.process(1, 4, 0., 0.).suppress, 1);
    assert_eq!(e.process(3, 0, 359., 0.).kind, 0);
    let action = e.process(3, 0, 360., 0.);
    assert_eq!(action.kind, 1);
    assert_eq!(action.code, 124);
    assert_eq!(e.process(3, 0, -900., 0.).kind, 0);
    assert_eq!(e.process(2, 4, -900., 0.).kind, 0);
    assert_eq!(e.process(3, 0, 1000., 0.).kind, 0);
    e.process(1, 4, 0., 0.);
    assert_eq!(e.process(3, 0, -360., 0.).code, 123);
}
#[test]
fn tap_then_hold_rearms_ten_thousand_times() {
    let mut e = engine();
    for _ in 0..10_000 {
        e.process(1, 4, 0., 0.);
        let tap = e.process(2, 4, 0., 0.);
        assert_eq!(tap.kind, 2);
        assert_eq!(tap.code, 4);
        assert_eq!(e.process(2, 4, 0., 0.).kind, 0);
        assert_eq!(e.process(3, 0, 1000., 0.).kind, 0);
        e.process(1, 4, 0., 0.);
        assert_eq!(e.process(3, 0, 360., 0.).kind, 1);
        assert_eq!(e.process(2, 4, 360., 0.).kind, 0);
    }
}
#[test]
fn click_action_replaces_tap_and_gesture_suppresses_click() {
    let mut c = config();
    c.enabled = true;
    c.bindings[1].click_action = Some("CMD+SHIFT+S".into());
    let mut e = Engine::default();
    e.configure(c).unwrap();
    assert_eq!(e.process(1, 4, 0., 0.).kind, 0);
    assert_eq!(e.process(1, 4, 50., 0.).kind, 0);
    e.process(3, 0, 100., 0.);
    assert_eq!(
        e.process(2, 4, 100., 0.),
        Outcome::chord(parse_chord("CMD+SHIFT+S").unwrap(), true)
    );
    assert_eq!(e.process(2, 4, 100., 0.).kind, 0);
    e.process(1, 4, 0., 0.);
    assert_eq!(e.process(3, 0, 360., 0.).code, 124);
    assert_eq!(e.process(2, 4, 360., 0.).kind, 0);
}
#[test]
fn all_directions_and_diagonal_dominance() {
    let mut e = engine();
    for (x, y, code) in [
        (-360., 0., 123),
        (360., 0., 124),
        (0., -360., 126),
        (0., 360., 125),
    ] {
        e.process(1, 4, 0., 0.);
        assert_eq!(e.process(3, 0, x, y).code, code);
        e.process(2, 4, x, y);
    }
    e.process(1, 4, 0., 0.);
    assert_eq!(e.process(3, 0, 360., 360.).kind, 0);
    assert_eq!(e.process(3, 0, 450., 360.).kind, 1);
}
#[test]
fn disabled_and_unconfigured_inputs_pass_unchanged() {
    let mut e = Engine::default();
    e.configure(config()).unwrap();
    assert_eq!(e.process(1, 4, 0., 0.), Outcome::default());
    assert_eq!(e.process(2, 4, 0., 0.), Outcome::default());
    let mut e = engine();
    for event in [1, 2, 4, 5] {
        assert_eq!(e.process(event, 0, 0., 0.), Outcome::default());
    }
}
#[test]
fn keyboard_repeat_and_release_action() {
    let mut c = config();
    c.enabled = true;
    c.bindings.push(Binding {
        trigger: "F13".into(),
        tap_passthrough: false,
        click_action: Some("CMD+C".into()),
        left: None,
        right: None,
        up: None,
        down: None,
    });
    let mut e = Engine::default();
    e.configure(c).unwrap();
    e.process(4, 105, 0., 0.);
    e.process(4, 105, 900., 0.);
    assert_eq!(e.process(5, 105, 0., 0.).code, 8);
    assert_eq!(e.process(5, 105, 0., 0.).kind, 0);
    e.process(4, 105, 0., 0.);
    assert_eq!(e.process(3, 0, 400., 0.).kind, 0);
    assert_eq!(e.process(5, 105, 400., 0.).kind, 0);
}
#[test]
fn disable_and_replace_drain_release_without_clicking() {
    let mut e = engine();
    e.process(1, 4, 0., 0.);
    e.disable();
    assert_eq!(
        e.process(2, 4, 0., 0.),
        Outcome {
            suppress: 1,
            ..Outcome::default()
        }
    );
    assert_eq!(e.process(1, 4, 0., 0.), Outcome::default());
    let mut e = engine();
    e.process(1, 4, 0., 0.);
    let mut c = config();
    c.enabled = true;
    c.bindings.clear();
    e.configure(c).unwrap();
    assert_eq!(e.process(2, 4, 0., 0.).suppress, 1);
    assert_eq!(e.process(1, 4, 0., 0.), Outcome::default());
}
#[test]
fn invalid_configuration_is_transactional() {
    let mut e = engine();
    e.process(1, 4, 0., 0.);
    let mut c = config();
    c.distance = 0.;
    assert!(e.configure(c).is_err());
    assert_eq!(e.process(3, 0, 360., 0.).kind, 1);
    for trigger in ["Mouse1", "Mouse2", "Mouse33", "CMD", "A", "F12", "F21"] {
        assert!(parse_trigger(trigger).is_err());
    }
    let mut c = config();
    c.bindings.push(c.bindings[0].clone());
    assert!(e.configure(c).is_err());
    let mut c = config();
    c.bindings[0].click_action = Some("CMD".into());
    assert!(e.configure(c).is_err());
}
#[test]
fn modifier_parser_requires_one_target_and_no_alias_duplicates() {
    assert_eq!(
        parse_chord(" cmd + shift + s ").unwrap(),
        Chord {
            code: 1,
            flags: (1 << 20) | (1 << 17)
        }
    );
    for s in [
        "",
        "CMD",
        "CMD+COMMAND+C",
        "CTRL+CTRL+C",
        "C+CMD",
        "CMD+C+V",
        "WIN+LEFT",
        "SHIFT+",
        "CMD+F21",
    ] {
        assert!(parse_chord(s).is_err(), "{s}");
    }
    assert!(parse_chord("CMD+[").is_ok());
    assert!(parse_chord("F20").is_ok());
}
#[test]
fn exact_replay_markers_only() {
    assert!(is_own(MARKER));
    assert!(is_own(0x455f3031));
    assert!(!is_own(0));
    assert!(!is_own(0x11111111455f3031));
}
#[test]
fn ffi_lifetime_errors_and_layout() {
    assert_eq!(std::mem::size_of::<Outcome>(), 24);
    unsafe {
        let e = gl_new();
        let bad = CString::new("{}").unwrap();
        assert_eq!(gl_configure(e, bad.as_ptr()), 0);
        assert!(!CStr::from_ptr(gl_error(e)).to_bytes().is_empty());
        let mut c = config();
        c.enabled = true;
        let json = CString::new(serde_json::to_string(&c).unwrap()).unwrap();
        assert_eq!(gl_configure(e, json.as_ptr()), 1);
        assert!(CStr::from_ptr(gl_error(e)).to_bytes().is_empty());
        assert_eq!(gl_process(e, 1, 4, 0., 0.).suppress, 1);
        gl_disable(e);
        assert_eq!(gl_process(e, 2, 4, 0., 0.).kind, 0);
        gl_free(e);
        assert_eq!(
            gl_process(std::ptr::null_mut(), 1, 4, 0., 0.),
            Outcome::default()
        );
        gl_free(std::ptr::null_mut());
    }
}
#[test]
fn config_roundtrip_and_unknown_fields() {
    let c = config();
    let value = serde_json::to_value(&c).unwrap();
    let restored: Config = serde_json::from_value(value.clone()).unwrap();
    assert_eq!(serde_json::to_value(restored).unwrap(), value);
    let mut bad = value;
    bad["typo"] = serde_json::json!(true);
    assert!(serde_json::from_value::<Config>(bad).is_err());
}

#[test]
fn keyboard_passthrough_is_a_single_release_result() {
    let mut c = config();
    c.enabled = true;
    c.bindings.push(Binding {
        trigger: "F20".into(),
        tap_passthrough: true,
        click_action: None,
        left: None,
        right: None,
        up: None,
        down: None,
    });
    let mut e = Engine::default();
    e.configure(c).unwrap();
    assert_eq!(e.process(4, 90, 0., 0.).kind, 0);
    e.process(4, 90, 0., 0.);
    assert_eq!(
        e.process(5, 90, 0., 0.),
        Outcome {
            suppress: 1,
            kind: 3,
            code: 90,
            flags: 0
        }
    );
    assert_eq!(e.process(5, 90, 0., 0.).kind, 0);
}

#[test]
fn simultaneous_holds_never_create_a_delayed_burst() {
    let mut e = engine();
    e.process(1, 3, 0., 0.);
    e.process(1, 4, 0., 0.);
    assert_eq!(e.process(3, 0, -360., 0.).kind, 1);
    assert_eq!(e.process(3, 0, -720., 0.).kind, 0);
    assert_eq!(e.process(2, 3, -720., 0.).kind, 0);
    assert_eq!(e.process(2, 4, -720., 0.).kind, 0);
    e.process(1, 4, 0., 0.);
    assert_eq!(e.process(3, 0, 360., 0.).code, 124);
}
