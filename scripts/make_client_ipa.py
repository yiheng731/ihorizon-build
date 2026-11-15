"""Pack Horizon's own iOS executable into an unsigned .ipa.

No Xcode, no xcodebuild, no codesign: an .ipa is a zip holding `Payload/<Name>.app/` with a
Mach-O executable named by `CFBundleExecutable` and an `Info.plist`. Sideloading tools
(Sideloadly, AltStore, Xcode's Devices window) sign the bundle themselves, so what they need is
exactly this - and building it here keeps the whole chain to `cargo build` plus a zip.

    python make_client_ipa.py --binary target/aarch64-apple-ios/release/horizon-client-ios

The executable is the workspace's `horizon-client-ios` bin (ios/crates/horizon-client-ios),
which starts `horizon_client::entry::main()`; winit's iOS backend runs UIApplicationMain from
there. See that crate's `src/main.rs` for how `--home`/`--resources` reach the game.
"""

from __future__ import annotations

import argparse
import plistlib
import shutil
import sys
import zipfile
from pathlib import Path

BUNDLE_NAME = "ihorizon"
BUNDLE_ID = "dev.horizon.client"
VERSION = "1.0"
MINIMUM_OS = "15.0"
EXECUTABLE_NAME = "ihorizon"

INFO_PLIST = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleExecutable": EXECUTABLE_NAME,
    "CFBundleIdentifier": BUNDLE_ID,
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": BUNDLE_NAME,
    "CFBundleDisplayName": BUNDLE_NAME,
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": VERSION,
    "CFBundleVersion": VERSION,
    "UIFileSharingEnabled": True,
    "LSSupportsOpeningDocumentsInPlace": True,
    "CFBundleDocumentTypes": [
        {
            "CFBundleTypeName": "ihorizon prepared files",
            "LSHandlerRank": "Owner",
            "LSItemContentTypes": ["public.zip-archive", "public.folder"],
        }
    ],
    "LSRequiresIPhoneOS": True,
    "MinimumOSVersion": MINIMUM_OS,
    "UIRequiredDeviceCapabilities": ["metal", "arm64"],
    "UIDeviceFamily": [1, 2],
    "UILaunchScreen": {"UIColorName": ""},
    "UIApplicationSupportsIndirectInputEvents": True,
    "UISupportedInterfaceOrientations": [
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    ],
    "UISupportedInterfaceOrientations~ipad": [
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    ],
    "CADisableMinimumFrameDurationOnPhone": True,
    "NSLocalNetworkUsageDescription": "ihorizon joins LAN worlds on your network.",
    "NSBonjourServices": ["_minecraft._tcp"],
    "UIRequiresFullScreen": True,
    "CFBundleSupportedPlatforms": ["iPhoneOS"],
    "DTSDKName": "iphoneos",
    "CFBundleIcons": {
        "CFBundlePrimaryIcon": {
            "CFBundleIconFiles": ["AppIcon60x60"],
            "CFBundleIconName": "AppIcon",
        }
    },
    "CFBundleIcons~ipad": {
        "CFBundlePrimaryIcon": {
            "CFBundleIconFiles": ["AppIcon60x60", "AppIcon76x76"],
            "CFBundleIconName": "AppIcon",
        }
    },
}

ICONS = {
    "AppIcon60x60@2x.png": 120,
    "AppIcon60x60@3x.png": 180,
    "AppIcon76x76@2x.png": 152,
    "AppIcon83.5x83.5@2x.png": 167,
    "AppIcon1024.png": 1024,
}
ICON_SOURCE = Path(__file__).resolve().parent.parent / "art" / "icon-horizon-1024.png"
ICON_DIR = Path(__file__).resolve().parent.parent / "ios" / "icons"

def write_icons(app: Path) -> bool:
    """Copy the drawn icon into the bundle at every size the system may ask for."""
    present = [name for name in ICONS if (ICON_DIR / name).is_file()]
    if len(present) == len(ICONS):
        for name in ICONS:
            shutil.copy2(ICON_DIR / name, app / name)
        return True
    if not ICON_SOURCE.is_file():
        return False
    try:
        from PIL import Image
    except ImportError:
        shutil.copy2(ICON_SOURCE, app / "AppIcon1024.png")
        return True
    source = Image.open(ICON_SOURCE).convert("RGBA")
    for name, size in ICONS.items():
        source.resize((size, size), Image.LANCZOS).save(app / name)
    return True

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", required=True, type=Path, help="the release executable")
    parser.add_argument("--out", type=Path, default=Path("dist/ihorizon-client-unsigned.ipa"))
    parser.add_argument("--keep", action="store_true", help="leave the assembled .app in build/")
    args = parser.parse_args()

    if not args.binary.is_file():
        print(f"✗ 找不到可执行文件：{args.binary}", file=sys.stderr)
        return 1
    if args.binary.read_bytes()[:4] != b"\xcf\xfa\xed\xfe":
        print(f"✗ {args.binary} 不是 arm64 Mach-O（cargo 编译失败？）", file=sys.stderr)
        return 1

    build = Path("build")
    app = build / "Payload" / f"{BUNDLE_NAME}.app"
    if app.parent.exists():
        shutil.rmtree(app.parent)
    app.mkdir(parents=True)

    executable = app / EXECUTABLE_NAME
    shutil.copy2(args.binary, executable)

    if not write_icons(app):
        print(f"⚠ 没有图标：{ICON_SOURCE} 不存在，装出来是白图标", file=sys.stderr)
    executable.chmod(0o755)

    with (app / "Info.plist").open("wb") as found:
        plistlib.dump(INFO_PLIST, found)
    (app / "PkgInfo").write_bytes(b"APPL????")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(app.parent.rglob("*")):
            archive.write(path, path.relative_to(build).as_posix())

    size = args.out.stat().st_size
    print(f"✓ {args.out}  {size / 1048576:.1f} MB")
    print(f"  bundle {BUNDLE_ID} {VERSION}，最低 iOS {MINIMUM_OS}，横屏，Metal + arm64")
    print(f"  可执行 {executable.stat().st_size / 1048576:.1f} MB（未签名，套壳工具会重签）")
    if not args.keep:
        shutil.rmtree(app.parent, ignore_errors=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
