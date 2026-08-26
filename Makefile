.PHONY: test coverage release clean

test:
	xcrun swift test

coverage:
	Scripts/check-coverage.sh

release:
	@test -n "$(VERSION)" || (echo "usage: make release VERSION=0.1.0" >&2; exit 64)
	Scripts/package-release.sh "$(VERSION)" dist
	Scripts/render-formula.sh "$(VERSION)" "dist/cellar-$(VERSION)-universal-apple-darwin.tar.gz" dist/cellar.rb

clean:
	xcrun swift package clean
