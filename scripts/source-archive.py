"""Create a source-only handoff; never include Windows builds, logs or certificates."""
import hashlib
from pathlib import Path
import plistlib
import zipfile

root = Path(__file__).resolve().parents[1]
with (root / "packaging" / "Info.plist").open("rb") as stream:
    version = plistlib.load(stream)["CFBundleShortVersionString"]
files = [p for p in root.iterdir() if p.is_file()]
for directory in ("core", "native", "packaging", "scripts", ".github"):
    for path in (root / directory).rglob("*"):
        if path.is_file() and not any(part in ("target", "__pycache__") for part in path.relative_to(root).parts):
            files.append(path)
for path in files:
    if path.suffix.lower() in (".p12", ".pfx", ".key", ".cer", ".log", ".exe", ".dll", ".msix"):
        raise SystemExit(f"Unexpected distribution content: {path.name}")
out = root / "dist"
out.mkdir(exist_ok=True)
archive = out / f"GestureLite-Mac-{version}-source.zip"
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as z:
    for path in sorted(files):
        relative = path.relative_to(root).as_posix()
        z.write(path, f"GestureLite-Mac/{relative}")
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n", encoding="ascii")
print(f"Source only; not a Mac installer: {archive}")
print(f"{len(files)} files; SHA256 {digest}")
