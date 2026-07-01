format:
	swiftformat MacLocker MacLockerTests Sources Tests

lint:
	swiftformat MacLocker MacLockerTests Sources Tests --lint

build:
	xcodebuild -project MacLocker.xcodeproj -scheme MacLocker -destination 'platform=macOS' -configuration Debug build

test:
	xcodebuild -project MacLocker.xcodeproj -scheme MacLocker -destination 'platform=macOS' test

verify: format lint build test

release:
	./scripts/package-release.sh

linux-build:
	swift build --product maclocker-niri

linux-test:
	swift test

linux-check: linux-build linux-test
