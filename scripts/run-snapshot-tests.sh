#!/usr/bin/env bash
set -euo pipefail
xcodebuild test -scheme ButterBar -only-testing:ButterBarTests/LibrarySnapshotTests -only-testing:ButterBarTests/PlayerHUDSnapshotTests -destination 'platform=macOS' "$@"
