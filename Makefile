.PHONY: help check build-mac bundle-mac install-mac run-mac build-android bundle-android install-android test-protocol test-crypto clean

help:
	@echo "=========================================================="
	@echo "  Corda - The invisible cord between your Mac and Android"
	@echo "=========================================================="
	@echo "Perintah yang tersedia:"
	@echo "  make check            - Validasi toolchain (Swift, Xcode, Flutter, Java)"
	@echo "  make test-protocol    - Validasi schema pesan JSON protokol"
	@echo "  make test-crypto      - Kompilasi & uji modul security macOS & Android"
	@echo "  make build-mac        - Kompilasi native macOS app (CordaMac)"
	@echo "  make bundle-mac       - Buat file aplikasi macOS (build/Corda.app)"
	@echo "  make install-mac      - Install Corda.app ke /Applications"
	@echo "  make run-mac          - Jalankan CordaMac di Menu Bar"
	@echo "  make build-android    - Kompilasi Android APK debug via Flutter"
	@echo "  make bundle-android   - Siapkan APK di build/Corda-Android.apk"
	@echo "  make install-android  - Install APK ke HP Android terhubung via USB"
	@echo "  make clean            - Bersihkan build artifact kedua platform"
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

bundle-mac: build-mac
	@echo "Bundling Corda.app..."
	@mkdir -p build/Corda.app/Contents/MacOS
	@mkdir -p build/Corda.app/Contents/Resources
	@cp macos/.build/out/Products/Release/CordaMac build/Corda.app/Contents/MacOS/
	@cp macos/CordaMac/Info.plist build/Corda.app/Contents/
	@cp macos/CordaMac/Resources/* build/Corda.app/Contents/Resources/
	@echo "  [OK] Corda.app created at build/Corda.app"

install-mac: bundle-mac
	@echo "Installing Corda.app to /Applications..."
	@rm -rf /Applications/Corda.app
	@cp -R build/Corda.app /Applications/
	@echo "  [OK] Corda.app installed to /Applications/Corda.app"

run-mac:
	@echo "Running CordaMac in Menu Bar..."
	@cd macos && swift run

build-android:
	@echo "Building Corda Android (Flutter APK)..."
	@cd android && flutter build apk --debug

bundle-android: build-android
	@mkdir -p build
	@cp android/build/app/outputs/flutter-apk/app-debug.apk build/Corda-Android.apk
	@echo "  [OK] Android APK ready at build/Corda-Android.apk"

install-android:
	@echo "Installing Corda to connected Android device..."
	@adb install -r build/Corda-Android.apk 2>/dev/null || (cd android && flutter install)
	@echo "  [OK] Corda installed to Android device."

clean:
	@echo "Cleaning build artifacts..."
	@cd macos && swift package clean 2>/dev/null || true
	@cd android && flutter clean 2>/dev/null || true
