.PHONY: check ipa preview assets clean fmt

CARGO ?= cargo
TARGET := aarch64-apple-ios

# 不需要 macOS：验证 Rust 侧在 iOS 目标上类型/API 全部成立。
check:
	$(CARGO) check --target $(TARGET) -p horizon-ios-shell --release

# 需要 macOS + Xcode + xcodegen（或直接用 CI）。
ipa:
	bash scripts/build_ipa.sh

# 任意平台：生成 ipa 布局预览，验证 Info.plist 与打包路径。
preview:
	python scripts/make_skeleton_ipa.py --preview --out build/Horizon-structure-preview.ipa

# 从你自己的 Minecraft 26.3 抽资源，产出 horizon-assets.zip。
assets:
	@test -n "$(HORIZON_REPO)" || (echo "先设 HORIZON_REPO=~/src/horizon"; exit 1)
	bash scripts/prepare_assets.sh $(SERVER_JAR)

clean:
	rm -rf build Horizon.xcodeproj
	$(CARGO) clean -p horizon-ios-shell
