#!/bin/bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 VERSION ARCHIVE OUTPUT_FILE" >&2
  exit 64
fi

release_version=$1
archive=$2
output_file=$3
project_root=$(cd "$(dirname "$0")/.." && pwd)

if [[ ! $release_version =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.-]+)?$ ]]; then
  echo "invalid version: $release_version" >&2
  exit 64
fi
if [[ ! -f $archive ]]; then
  echo "archive not found: $archive" >&2
  exit 66
fi

archive_sha=$(shasum -a 256 "$archive" | awk '{print $1}')
escaped_version=${release_version//&/\\&}
sed -e "s/@VERSION@/$escaped_version/g" -e "s/@SHA256@/$archive_sha/g" \
  "$project_root/Packaging/Homebrew/cellar.rb.in" > "$output_file"
ruby -c "$output_file" >/dev/null
