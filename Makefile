.PHONY: help check build-mac run-mac build-android test-protocol test-crypto clean

help:
	@echo "=========================================================="
	@echo "  Corda - The invisible cord between your Mac and Android"
	@echo "=========================================================="
	@echo "Perintah yang tersedia:"
	@echo "  make check          - Validasi toolchain (Swift, Xcode, Flutter, Java)"
	@echo "  make test-protocol  - Validasi schema pesan JSON protokol"
	@echo "  make test-crypto    - Kompilasi & uji modul security macOS & Android"
	@echo "  make build-mac      - Kompilasi native macOS app (CordaMac)"
	@echo "  make run-mac        - Jalankan CordaMac di Menu Bar"
	@echo "  make build-android  - Kompilasi Android APK debug via Flutter"
	@echo "  make clean          - Bersihkan build artifact kedua platform"
	@echo "=========================================================="

check:
	@echo "Checking toolchains..."
	@which swift > /dev/null && echo "  [OK] Swift: $$(swift --version | head -n 1)" || echo "  [MISSING] Swift"
	@which xcodebuild > /dev/null && echo "  [OK] Xcode: $$(xcodebuild -version | head -n 1)" || echo "  [MISSING] xcodebuild"
	@which flutter > /dev/null && echo "  [OK] Flutter: $$(flutter --version | head -n 1)" || echo "  [MISSING] Flutter"
	@which java > /dev/null && echo "  [OK] Java: $$(java -version 2>&1 | head -n 1)" || echo "  [MISSING] Java"

test-protocol:
	@echo "Validating JSON schemas..."
	@python3 scripts/validate_schemas.py

test-crypto:
	@echo "Testing macOS Security module..."
	@cd macos && swift build
	@echo "Testing Android Security module..."
	@cd android/android && ./gradlew compileDebugKotlin --quiet

build-mac:
	@echo "Building CordaMac (macOS)..."
	@cd macos && swift build -c release

run-mac:
	@echo "Running CordaMac in Menu Bar..."
	@cd macos && swift run

build-android:
	@echo "Building Corda Android (Flutter APK)..."
	@cd android && flutter build apk --debug

clean:
	@echo "Cleaning build artifacts..."
	@cd macos && swift package clean 2>/dev/null || true
	@cd android && flutter clean 2>/dev/null || true
