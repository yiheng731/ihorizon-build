"""Assemble an ipa from a built Horizon.app, or — on a machine without Xcode —
from the bundle *layout* only, so the packaging step is verifiable anywhere.

    python scripts/make_skeleton_ipa.py --app build/Payload/Horizon.app --out build/Horizon.ipa
    python scripts/make_skeleton_ipa.py --preview --out build/Horizon-structure-preview.ipa

`--preview` substitutes the Xcode build variables in Info.plist, adds PkgInfo and
an empty executable marker, and writes a structurally correct (but not
installable) ipa. It exists to prove Info.plist, bundle layout and the zip
writer are right before spending ten minutes on a macOS build.
"""

from __future__ import annotations

import argparse
import plistlib
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
INFO_PLIST = ROOT / "ios" / "Horizon" / "Info.plist"

BUILD_SETTINGS = {
    "EXECUTABLE_NAME": "Horizon",
    "PRODUCT_NAME": "Horizon",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.horizon.client",
    "DEVELOPMENT_LANGUAGE": "en",
    "TARGET_NAME": "Horizon",
}

def substitute(value):
    """Resolve $(VAR) exactly like Xcode's Info.plist preprocessing."""
    if isinstance(value, str):
        for key, replacement in BUILD_SETTINGS.items():
            value = value.replace(f"$({key})", replacement)
        if "$(" in value:
            raise SystemExit(f"Info.plist 里有未定义的构建设置：{value}")
        return value
    if isinstance(value, dict):
        return {key: substitute(item) for key, item in value.items()}
    if isinstance(value, list):
        return [substitute(item) for item in value]
    return value

def build_preview(destination: Path) -> None:
    app = destination / "Payload" / "Horizon.app"
    if app.parent.parent.exists():
        shutil.rmtree(destination / "Payload", ignore_errors=True)
    app.mkdir(parents=True, exist_ok=True)

    with INFO_PLIST.open("rb") as handle:
        info = substitute(plistlib.load(handle))
    with (app / "Info.plist").open("wb") as handle:
        plistlib.dump(info, handle, fmt=plistlib.FMT_BINARY)

    (app / "PkgInfo").write_bytes(b"APPL????")
    (app / "PREVIEW-ONLY.txt").write_text(
        "This ipa contains no executable. Build the real one with\n"
        "  bash scripts/build_ipa.sh            (macOS / CI)\n",
        encoding="utf-8",
    )
    print(f"  bundle  {app}")
    print(f"  id      {info['CFBundleIdentifier']}  v{info['CFBundleShortVersionString']}")

def package(source_root: Path, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(source_root.rglob("*")):
            if path.is_dir():
                continue
            archive.write(path, path.relative_to(source_root).as_posix())
    print(f"  ipa     {out}  ({out.stat().st_size / 1024:.0f} KiB)")

    with zipfile.ZipFile(out) as archive:
        bad = archive.testzip()
        if bad:
            raise SystemExit(f"ipa 损坏：{bad}")
        names = archive.namelist()
    expected = "Payload/Horizon.app/Info.plist"
    if expected not in names:
        raise SystemExit(f"ipa 缺少 {expected}；实际内容：{names[:5]}")
    print(f"  check   {len(names)} entries, {expected} present")

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="已构建的 Horizon.app 目录")
    parser.add_argument("--preview", action="store_true", help="只生成布局（无 Mach-O）")
    parser.add_argument("--out", type=Path, default=ROOT / "build" / "Horizon.ipa")
    args = parser.parse_args()

    if args.app:
        if not (args.app / "Info.plist").exists():
            raise SystemExit(f"{args.app} 不像 .app 目录")
        staging = args.out.parent / "_stage"
        shutil.rmtree(staging, ignore_errors=True)
        (staging / "Payload").mkdir(parents=True)
        shutil.copytree(args.app, staging / "Payload" / args.app.name, symlinks=True)
        package(staging, args.out)
        shutil.rmtree(staging, ignore_errors=True)
        return 0

    if not args.preview:
        parser.error("要么给 --app，要么给 --preview")
    staging = args.out.parent / "_preview"
    shutil.rmtree(staging, ignore_errors=True)
    build_preview(staging)
    package(staging, args.out)
    shutil.rmtree(staging, ignore_errors=True)
    return 0

if __name__ == "__main__":
    sys.exit(main())
