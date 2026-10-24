APP_NAME   := NotchPrompter
CONFIG     ?= Release
# Outside the project on purpose: iCloud-synced folders (Desktop/Documents) add extended
# attributes that make codesign fail with "resource fork, Finder information … not allowed".
BUILD_DIR  := $(HOME)/Library/Developer/NotchPrompter/DerivedData
APP        := $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app

.PHONY: all generate build run stop install clean voice-sim tracker-sim

all: build

generate:
	@command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
	xcodegen generate --quiet

build: generate
	xcodebuild \
		-project $(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) \
		-destination 'platform=macOS,arch=arm64' \
		-quiet \
		build
	@echo "Built $(APP)"

stop:
	@pkill -x $(APP_NAME) 2>/dev/null || true

run: build stop
	open "$(APP)"

install: build stop
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	open "/Applications/$(APP_NAME).app"

clean:
	rm -rf $(BUILD_DIR) $(APP_NAME).xcodeproj

# Offline test of the voice gate with synthesized Czech + English speech (no microphone needed).
SIM_DIR := $(BUILD_DIR)/voice-sim
voice-sim:
	@mkdir -p "$(SIM_DIR)"
	@say -v Zuzana --file-format=WAVE --data-format=LEF32@48000 -o "$(SIM_DIR)/cs.wav" \
		"Dobrý den, vítejte u dnešního videa. Dnes si ukážeme, jak funguje čtecí zařízení přímo pod kamerou."
	@say -v Daniel --file-format=WAVE --data-format=LEF32@48000 -o "$(SIM_DIR)/en.wav" \
		"Hello and welcome back. Today I want to show you how this teleprompter works, right under the camera."
	@swiftc -O -o "$(SIM_DIR)/sim" NotchPrompter/Voice/SpeechGate.swift Tools/SpeechGateSim/main.swift
	@"$(SIM_DIR)/sim" "$(SIM_DIR)"

# Offline test of word tracking: a simulated speaker and recognizer with realistic mistakes.
tracker-sim:
	@mkdir -p "$(BUILD_DIR)/tracker-sim"
	@swiftc -O -o "$(BUILD_DIR)/tracker-sim/sim" NotchPrompter/Scripts/ScriptTokens.swift \
		NotchPrompter/Voice/WordMatcher.swift Tools/TrackerSim/main.swift
	@"$(BUILD_DIR)/tracker-sim/sim"
