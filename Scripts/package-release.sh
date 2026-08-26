#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 VERSION OUTPUT_DIRECTORY" >&2
  exit 64
fi

release_version=$1
output_directory=$2
project_root=$(cd "$(dirname "$0")/.." && pwd)
stage_directory=$(mktemp -d "${TMPDIR:-/tmp}/cellar-release.XXXXXX")
trap 'rm -rf "$stage_directory"' EXIT

if [[ ! $release_version =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
  echo "invalid version: $release_version" >&2
  exit 64
fi

source_version=$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' "$project_root/Sources/CellarCore/CellarApplication.swift")
if [[ $source_version != "$release_version" ]]; then
  echo "source version $source_version does not match release $release_version" >&2
  exit 65
fi

cd "$project_root"
xcrun swift build -c release --arch arm64 --arch x86_64

package_name="cellar-$release_version-universal-apple-darwin"
package_directory="$stage_directory/$package_name"
mkdir -p "$package_directory" "$output_directory"
cp .build/apple/Products/Release/cellar "$package_directory/cellar"
cp LICENSE README.md "$package_directory/"
chmod 755 "$package_directory/cellar"
tar -C "$stage_directory" -czf "$output_directory/$package_name.tar.gz" "$package_name"
shasum -a 256 "$output_directory/$package_name.tar.gz" > "$output_directory/$package_name.tar.gz.sha256"

echo "$output_directory/$package_name.tar.gz"
