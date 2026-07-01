format:
	swiftformat MacLocker MacLockerTests

lint:
	swiftformat MacLocker MacLockerTests --lint

build:
	xcodebuild -project MacLocker.xcodeproj -scheme MacLocker -destination 'platform=macOS' -configuration Debug build

test:
	xcodebuild -project MacLocker.xcodeproj -scheme MacLocker -destination 'platform=macOS' test

verify: format lint build test

release:
	./scripts/package-release.sh
