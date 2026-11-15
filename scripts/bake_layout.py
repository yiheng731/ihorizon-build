"""Bake a saved `touch_layout.json` into the client, so a fresh install starts with it.

The layout a person drags in `tools/touch_layout_editor.py` is written to disk as JSON. This
script puts that JSON into the render crate as `touch_hud::BAKED`, which is what the client
writes the first time it runs when the file is not there yet. Regenerate patch 0014 after.

Usage:
    python scripts/bake_layout.py tools/touch_layout.json
    python scripts/bake_layout.py --clear
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = Path("crates/horizon-client-render/src/touch_hud.rs")
TREES = []

EMPTY = 'pub const BAKED: &str = "";'

def target() -> Path:
    for tree in TREES:
        candidate = tree / SOURCE
        if candidate.exists():
            return candidate
    raise SystemExit(f"no patched tree with {SOURCE} found; looked in {[str(t) for t in TREES]}")

def main(argv: list[str]) -> int:
    path = target()
    source = path.read_text(encoding="utf-8")
    if "--clear" in argv:
        layout = None
    else:
        if len(argv) < 2:
            return int(bool(sys.stderr.write(__doc__ or "")))
        layout = json.loads(Path(argv[1]).read_text(encoding="utf-8"))
        layout["edit"] = False
        layout["debug"] = False
        if "buttons" not in layout or not layout["buttons"]:
            return int(bool(sys.stderr.write("layout has no buttons\n")))

    if layout is None:
        replacement = EMPTY
        note = "cleared the baked layout"
    else:
        pretty = json.dumps(layout, indent=2, sort_keys=True)
        escaped = pretty.replace("\\", "\\\\").replace('"', '\\"')
        literal = "\n".join(f'    "{line}",' for line in escaped.splitlines())
        replacement = (
            "/// A layout baked into the build, so a fresh install starts where the person put the\n"
            "/// controls instead of where the defaults are. Empty means the defaults are written.\n"
            f"pub const BAKED: &str = concat!(\n{literal}\n);"
        )
        note = f"baked {len(layout['buttons'])} buttons from {argv[1]}"

    pattern = re.compile(r'(?:/// A layout baked into the build[^\n]*\n(?:///[^\n]*\n)?)?pub const BAKED: &str = [^;]*;', re.S)
    if not pattern.search(source):
        return int(bool(sys.stderr.write(f"no BAKED slot in {path}\n")))
    path.write_text(pattern.sub(lambda _m: replacement, source, count=1), encoding="utf-8", newline="\n")
    print(f"{note}: {path}")
    print("now regenerate patches/0014 and rebuild")
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
