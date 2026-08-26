# Contributing

Cellar targets macOS 14+ and Swift 6. Keep changes native, dependency-free at runtime, and conservative about deletion advice.

Before opening a change:

```sh
swift test
Scripts/check-coverage.sh
swift build -c release --arch arm64 --arch x86_64
```

Add a failing regression test before changing behavior. Never collect command text, arguments, environment contents, or other data unnecessary for package-level usage evidence. Changes that broaden candidate eligibility should document the false-positive risk.
