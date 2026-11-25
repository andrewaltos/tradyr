APP_NAME := Tradyr
BUNDLE_ID := dev.tradyr.app
APP := .build/$(APP_NAME).app
INSTALLED := /Applications/$(APP_NAME).app

.PHONY: all build test bundle install run icon identity reset-perms verify-offline clean

all: bundle

build:
	swift build

## Command Line Tools ships the swift-testing macro plugin somewhere SwiftPM does
## not look by default, so point the compiler at it explicitly.
TESTING_PLUGINS := $(shell dirname $(shell dirname $(shell xcrun --find swift)))/lib/swift/host/plugins/testing

test:
	swift test -Xswiftc -plugin-path -Xswiftc "$(TESTING_PLUGINS)"

bundle:
	@Scripts/make-bundle.sh

## Replace the installed copy in place, so Spotlight and the TCC records stay put.
install: bundle
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@rm -rf "$(INSTALLED)"
	@cp -R "$(APP)" "$(INSTALLED)"
	@echo "==> installed $(INSTALLED)"

run: install
	@open "$(INSTALLED)"

icon:
	@Scripts/make-icns.sh

identity:
	@Scripts/make-identity.sh

## Forget the microphone, speech and system-audio grants, e.g. to re-test first launch.
reset-perms:
	tccutil reset All $(BUNDLE_ID)

## The "all on device" promise, checked against the shipped binary.
verify-offline: bundle
	@if strings "$(APP)/Contents/MacOS/$(APP_NAME)" \
		| grep -inE 'https?://|URLSession|firebase|crashlytics|analytics'; then \
		echo "!!! network or telemetry symbols found" >&2; exit 1; \
	else \
		echo "==> clean: no network or telemetry symbols"; \
	fi

clean:
	swift package clean
	rm -rf .build/$(APP_NAME).app .build/AppIcon.iconset
