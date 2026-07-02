# gab — push-to-talk Whisper dictation
# Targets:
#   make whisper   build vendored whisper.cpp static libs (run once)
#   make sign      create the stable gab-dev signing identity (run once)
#   make           build the gab.app bundle (dev: model loads from App Support)
#   make run       build + launch
#   make install   copy gab.app into /Applications
#   make release   build a self-contained app with the model bundled inside
#   make dmg       build a drag-to-install gab.dmg (implies release)
#   make clean     remove build-app/

APP        := gab
BUNDLE     := build-app/$(APP).app
CONTENTS   := $(BUNDLE)/Contents
MACOS_DIR  := $(CONTENTS)/MacOS
RES_DIR    := $(CONTENTS)/Resources
BIN        := $(MACOS_DIR)/$(APP)

# Model bundled into release builds / the dmg (balanced size vs accuracy).
RELEASE_MODEL := ggml-small.en.bin
MODEL_SRC     := $(HOME)/Library/Application Support/gab/$(RELEASE_MODEL)

SWIFT_SRCS := $(wildcard Sources/$(APP)/*.swift)
DIST       := vendor/dist
WHISPER_LIBS := \
	$(DIST)/lib/libwhisper.a \
	$(DIST)/lib/libggml.a \
	$(DIST)/lib/libggml-cpu.a \
	$(DIST)/lib/libggml-metal.a \
	$(DIST)/lib/libggml-blas.a \
	$(DIST)/lib/libggml-base.a

FRAMEWORKS := \
	-framework AppKit -framework Foundation -framework AVFoundation \
	-framework CoreGraphics -framework CoreAudio -framework AudioToolbox \
	-framework Metal -framework Accelerate

# Sign the bundle: prefer the stable gab-dev cert, fall back to ad-hoc.
define sign_bundle
	if codesign --force --deep --sign gab-dev $(BUNDLE) >/dev/null 2>&1; then \
		echo "signed: gab-dev (stable — grants persist)"; \
	else \
		codesign --force --deep --sign - $(BUNDLE) >/dev/null 2>&1 || true; \
		echo "signed: ad-hoc (run 'make sign' so grants persist across rebuilds)"; \
	fi
endef

.PHONY: all whisper sign run install release dmg clean

all: $(BIN)

$(WHISPER_LIBS):
	./scripts/setup-whisper.sh

whisper:
	./scripts/setup-whisper.sh

sign:
	./scripts/setup-signing.sh

$(BIN): $(SWIFT_SRCS) $(WHISPER_LIBS) Resources/Info.plist Resources/AppIcon.icns
	@mkdir -p $(MACOS_DIR) $(RES_DIR)
	swiftc -O \
		-target arm64-apple-macos13.0 \
		-o $(BIN) \
		$(SWIFT_SRCS) \
		-I Sources/CWhisper \
		-Xcc -I$(DIST)/include \
		$(WHISPER_LIBS) \
		-lc++ \
		$(FRAMEWORKS)
	@cp Resources/Info.plist $(CONTENTS)/Info.plist
	@cp Resources/AppIcon.icns $(RES_DIR)/AppIcon.icns
	@$(sign_bundle)
	@echo "Built $(BUNDLE)"

run: $(BIN)
	@pkill -x $(APP) >/dev/null 2>&1 || true
	open $(BUNDLE)

install: $(BIN)
	@pkill -x $(APP) >/dev/null 2>&1 || true
	@rm -rf /Applications/$(APP).app
	@cp -R $(BUNDLE) /Applications/
	@echo "Installed /Applications/$(APP).app"

# Self-contained build: same app with the model copied into Resources, re-signed.
release: $(BIN)
	@mkdir -p $(RES_DIR)
	@if [ -f "$(MODEL_SRC)" ]; then \
		cp "$(MODEL_SRC)" "$(RES_DIR)/$(RELEASE_MODEL)"; \
		echo "bundled model: $(RELEASE_MODEL)"; \
	else \
		echo "ERROR: $(MODEL_SRC) not found — run ./scripts/fetch-model.sh small.en"; exit 1; \
	fi
	@$(sign_bundle)
	@echo "Release bundle ready: $(BUNDLE) ($$(du -sh $(BUNDLE) | cut -f1))"

dmg: release
	@rm -f build-app/$(APP).dmg
	@rm -rf build-app/dmgroot && mkdir -p build-app/dmgroot
	@cp -R $(BUNDLE) build-app/dmgroot/
	@ln -s /Applications build-app/dmgroot/Applications
	hdiutil create -volname "$(APP)" -srcfolder build-app/dmgroot \
		-ov -format UDZO build-app/$(APP).dmg
	@rm -rf build-app/dmgroot
	@echo "Built build-app/$(APP).dmg ($$(du -sh build-app/$(APP).dmg | cut -f1))"

clean:
	rm -rf build-app
