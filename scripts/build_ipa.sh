#!/usr/bin/env bash
# Build Horizon.ipa for iOS (unsigned by default).
#
# Runs on macOS with Xcode + xcodegen, or verbatim on a GitHub Actions
# macos-15 runner (.github/workflows/ios-ipa.yml).
#
#   ./scripts/build_ipa.sh                # unsigned ipa
#   SIGN_IDENTITY="Apple Development: you@x" ./scripts/build_ipa.sh
#   ZSIGN_CERT=cert.p12 ZSIGN_PASSWORD=x ZSIGN_PROFILE=app.mobileprovision ./scripts/build_ipa.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG=Release
SCHEME=Horizon
BUILD="$ROOT/build"

export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"

step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

step "Rust 1/2: toolchain"
if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo 缺失：curl https://sh.rustup.rs -sSf | sh -sY" >&2
  exit 1
fi
rustup target add aarch64-apple-ios >/dev/null 2>&1 || true

step "Rust 2/2: libhorizon_ios_shell.a (aarch64-apple-ios, release)"
cd "$ROOT"
cargo build --release --target aarch64-apple-ios -p horizon-ios-shell
LIB="$ROOT/target/aarch64-apple-ios/release/libhorizon_ios_shell.a"
[[ -f "$LIB" ]] || { echo "静态库没生成：$LIB" >&2; exit 1; }
echo "    $(ls -lh "$LIB" | awk '{print $5}')  $LIB"

step "Xcode 1/3: 生成工程"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen 缺失：brew install xcodegen" >&2
  exit 1
fi
xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT"

step "Xcode 2/3: 编译 app（不签名）"
rm -rf "$BUILD"
xcodebuild \
  -project "$ROOT/Horizon.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -derivedDataPath "$BUILD" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -quiet \
  build

APP="$BUILD/Build/Products/$CONFIG-iphoneos/Horizon.app"
[[ -d "$APP" ]] || { echo "app 没产出：$APP" >&2; exit 1; }
plutil -lint "$APP/Info.plist"

step "Xcode 3/3: 打包 ipa"
rm -rf "$BUILD/Payload"
mkdir -p "$BUILD/Payload"
cp -R "$APP" "$BUILD/Payload/Horizon.app"
cd "$BUILD"
rm -f Horizon-unsigned.ipa
# -y 保留符号链接（Frameworks 里的 framework 版本链接），-q 安静，-r 递归。
zip -qry Horizon-unsigned.ipa Payload
IPA="$BUILD/Horizon-unsigned.ipa"
echo "    $(ls -lh "$IPA" | awk '{print $5}')  $IPA"

if [[ -n "${ZSIGN_CERT:-}" ]]; then
  step "签名（zsign + 开发者证书）"
  command -v zsign >/dev/null || { echo "zsign 缺失：https://github.com/zhlynn/zsign" >&2; exit 1; }
  zsign -k "$ZSIGN_CERT" -p "${ZSIGN_PASSWORD:-}" ${ZSIGN_PROFILE:+-m "$ZSIGN_PROFILE"} \
        -o "$BUILD/Horizon.ipa" "$IPA"
  IPA="$BUILD/Horizon.ipa"
elif [[ -n "${SIGN_IDENTITY:-}" ]]; then
  step "签名（codesign，需已装好的描述文件）"
  codesign --force --deep --sign "$SIGN_IDENTITY" "$BUILD/Payload/Horizon.app"
  rm -f "$BUILD/Horizon.ipa"
  (cd "$BUILD" && zip -qry Horizon.ipa Payload)
  IPA="$BUILD/Horizon.ipa"
else
  echo
  echo "未签名 ipa。装进手机的三条路："
  echo "  1) Sideloadly / AltStore（Windows 即可，Apple ID 签 7 天）"
  echo "  2) 付费开发者账号 + Ad Hoc 描述文件"
  echo "  3) 越狱设备：scp 到 /Applications 后 uicache -a"
fi

echo
echo "完成：$IPA"
