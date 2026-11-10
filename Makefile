SHELL := /bin/bash

.PHONY: setup build test app run verify verify-live verify-loop agent-test install install-cli clean

setup:
	./scripts/setup.sh

build:
	swift build

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	open "dist/MotoMirror.app"

verify:
	./scripts/verify.sh

verify-live:
	./scripts/verify.sh --live --target moto --wait-for-device 120

verify-loop:
	./scripts/verify-loop.sh 0 600

agent-test:
	python3 verify/agent_features.py

install:
	./scripts/install.sh

install-cli: build
	mkdir -p $$HOME/.local/bin
	cp .build/debug/motomirrorctl $$HOME/.local/bin/motomirrorctl
	chmod +x $$HOME/.local/bin/motomirrorctl

clean:
	rm -rf .build dist
	rm -rf Resources/AppIcon.icns Resources/AppIcon.iconset
