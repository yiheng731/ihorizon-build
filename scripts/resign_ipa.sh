#!/usr/bin/env bash
set -euo pipefail

IN_IPA="${1:?用法: resign_ipa.sh in.ipa out.ipa TEAMID profile.mobileprovision}"
OUT_IPA="${2:?缺 out.ipa}"
TEAM_ID="${3:?缺 TEAMID}"
PROFILE="${4:?缺 mobileprovision 路径}"
ENTITLEMENTS="${ENTITLEMENTS:-}"
IDENTITY="${SIGN_IDENTITY:-Apple Distribution: $TEAM_ID}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

unzip -q "$IN_IPA" -d "$WORK"
APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)"
[[ -d "$APP" ]] || { echo "ipa 里没有 .app" >&2; exit 1; }

if [[ -z "$ENTITLEMENTS" ]]; then
  ENTITLEMENTS="$WORK/derived.entitlements"
  security cms -D -i "$PROFILE" > "$WORK/profile.plist"
  /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$WORK/profile.plist" > "$ENTITLEMENTS"
fi

cp "$PROFILE" "$APP/embedded.mobileprovision"

if [[ -d "$APP/Frameworks" ]]; then
  find "$APP/Frameworks" -name '*.framework' -maxdepth 2 -print0 | while IFS= read -r -d '' fw; do
    codesign --force --timestamp=none --sign "$IDENTITY" "$fw"
  done
  find "$APP/Frameworks" -name '*.dylib' -print0 | while IFS= read -r -d '' dylib; do
    codesign --force --timestamp=none --sign "$IDENTITY" "$dylib"
  done
fi

codesign --force --timestamp=none \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

rm -f "$OUT_IPA"
(cd "$WORK" && zip -qry "$OUT_IPA" Payload)
echo "已签名：$OUT_IPA"
