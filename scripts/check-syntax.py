"""Optional developer check. Syntax parsing is not a macOS SDK compile.

Install tree-sitter, tree-sitter-swift and PyYAML in a disposable environment.
No packages from this check are part of the Mac application.
"""
import json
import plistlib
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
local_tools = ROOT / "verification" / "python-tools"
if local_tools.exists():
    sys.path.insert(0, str(local_tools))
import tree_sitter  # noqa: E402
import tree_sitter_swift  # noqa: E402
import yaml  # noqa: E402

parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
failures = []
sources = sorted((ROOT / "native").glob("*.swift"))
for path in sources:
    tree = parser.parse(path.read_bytes())
    if tree.root_node.has_error:
        stack = [tree.root_node]
        while stack:
            node = stack.pop()
            if node.type == "ERROR" or node.is_missing:
                failures.append(f"{path.name}:{node.start_point.row + 1}:{node.start_point.column + 1} {node.type}")
            stack.extend(reversed(node.children))
    else:
        print(f"Swift syntax parsed: {path.name}")
with (ROOT / "packaging" / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
assert info["CFBundleExecutable"] == "GestureLite"
assert info["LSMinimumSystemVersion"] == "13.0"
assert info["LSUIElement"] is True
workflow = yaml.load((ROOT / ".github" / "workflows" / "build.yml").read_text(), Loader=yaml.BaseLoader)
assert workflow["permissions"] == {"contents": "read"}
assert "workflow_dispatch" in workflow["on"]
assert workflow["jobs"]["mac-preview"]["strategy"]["matrix"]["os"] == ["macos-15", "macos-15-intel"]
assert workflow["jobs"]["publish-preview"]["needs"] == ["prepare-source", "mac-preview"]
assert workflow["jobs"]["publish-preview"]["permissions"] == {"contents": "write"}
assert "pull_request" in workflow["jobs"]["publish-preview"]["if"]
json.loads((ROOT / "core" / "config.example.json").read_text())
if failures:
    raise SystemExit("\n".join(failures))
print("Plist, workflow and example JSON checked. Native macOS type checking/linking NOT performed.")
