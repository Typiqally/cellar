#!/bin/bash
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
coverage_minimum=${CELLAR_COVERAGE_MINIMUM:-80}
cd "$project_root"

xcrun swift test --enable-code-coverage
test_binary=$(find .build -path '*/debug/CellarPackageTests.xctest/Contents/MacOS/CellarPackageTests' -type f -print -quit)
profile=$(find .build -path '*/debug/codecov/default.profdata' -type f -print -quit)
if [[ -z $test_binary || -z $profile ]]; then
  echo "coverage artifacts were not produced" >&2
  exit 1
fi

report=$(xcrun llvm-cov report "$test_binary" \
  -instr-profile "$profile" \
  -ignore-filename-regex='(Tests|Sources/CellarCLI)')
printf '%s\n' "$report"
line_coverage=$(printf '%s\n' "$report" | awk '$1 == "TOTAL" { gsub(/%/, "", $10); print $10 }')
if [[ -z $line_coverage ]]; then
  echo "could not read total line coverage" >&2
  exit 1
fi
awk -v actual="$line_coverage" -v minimum="$coverage_minimum" 'BEGIN {
  if (actual + 0 < minimum + 0) {
    printf "line coverage %.2f%% is below %.2f%%\n", actual, minimum > "/dev/stderr"
    exit 1
  }
}'
