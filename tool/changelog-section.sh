#!/usr/bin/env bash
# Prints the CHANGELOG.md section of one version (release-body text).
# Usage: tool/changelog-section.sh 1.0.1
set -euo pipefail
awk -v v="$1" '
  /^## \[/ { on = index($0, "[" v "]") == 4 }
  on && !/^## \[/ { print }
' "$(dirname "$0")/../CHANGELOG.md" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
