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

linux-test:
	python3 -m unittest discover -s linux/tests

linux-check:
	python3 -m py_compile linux/maclocker_niri.py
	python3 -m unittest discover -s linux/tests
