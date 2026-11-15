.PHONY: check ipa preview assets clean fmt

CARGO ?= cargo
TARGET := aarch64-apple-ios

check:
	$(CARGO) check --target $(TARGET) -p horizon-ios-shell --release

ipa:
	bash scripts/build_ipa.sh

preview:
	python scripts/make_skeleton_ipa.py --preview --out build/Horizon-structure-preview.ipa

assets:
	@test -n "$(HORIZON_REPO)" || (echo "先设 HORIZON_REPO=~/src/horizon"; exit 1)
	bash scripts/prepare_assets.sh $(SERVER_JAR)

clean:
	rm -rf build Horizon.xcodeproj
	$(CARGO) clean -p horizon-ios-shell
