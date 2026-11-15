#!/usr/bin/env bash
# Desktop side of plan B: turn the player's own Minecraft 26.3 into the
# horizon-assets.zip that the iOS app imports on first launch.
#
# Needs: Rust 1.90+, Python 3.11+, JDK 25, and the Horizon checkout.
#
#   HORIZON_REPO=~/src/horizon ./scripts/prepare_assets.sh ~/Downloads/server.jar
#
# Nothing Mojang-made is downloaded by this script or by the app: it reads the
# jar/Minecraft installation you already own.
set -euo pipefail

SERVER_JAR="${1:-$HOME/Downloads/server.jar}"
: "${HORIZON_REPO:?请先设置 HORIZON_REPO=指向 horizon 仓库根目录}"
OUT="${OUT:-$HORIZON_REPO/dist/horizon-assets.zip}"

step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

[[ -f "$SERVER_JAR" ]] || { echo "找不到 server.jar：$SERVER_JAR" >&2; exit 1; }
command -v java >/dev/null || { echo "缺 JDK 25（horizon-prepare 会用它读 jar）" >&2; exit 1; }

cd "$HORIZON_REPO"

step "horizon-prepare：抽 assets + data"
cargo run --release -p horizon-prepare -- --prepare --server-jar "$SERVER_JAR"

step "horizon-prepare sounds：抽音频"
cargo run --release -p horizon-prepare sounds

step "写清单"
mkdir -p "$(dirname "$OUT")"
{
  echo "format = 1"
  echo "producer = horizon-ios/prepare_assets.sh"
  echo "date = $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "server_jar = $(basename "$SERVER_JAR")"
  echo "server_jar_sha256 = $(shasum -a 256 "$SERVER_JAR" | awk '{print $1}')"
  echo "host = $(uname -srm)"
} > .local/MANIFEST.txt
if [[ -f "$HORIZON_REPO/research-lock.json" ]]; then
  echo "research_lock = $(shasum -a 256 "$HORIZON_REPO/research-lock.json" | awk '{print $1}')" >> .local/MANIFEST.txt
fi

step "打包"
rm -f "$OUT"
# 越小越好：iOS 端一次性解压，压缩比直接决定传输和导入时间。
(cd .local && zip -qr9 "$OUT" assets data MANIFEST.txt)
echo "    $(ls -lh "$OUT" | awk '{print $5}')  $OUT"

cat <<'EOF'

下一步（三选一）：
  * 数据线：Finder → 设备 → 文件 → Horizon → 拖进 horizon-assets.zip
  * 隔空投送 zip 到手机 → 用「文件」App 打开 → 分享到 Horizon
  * 或直接把 .local 目录整份拷进 App 沙盒的 Documents（越狱/调试）

然后打开 Horizon → 导入 zip → 开始游戏。
EOF
