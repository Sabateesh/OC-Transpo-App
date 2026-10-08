#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/oc-speed-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swiftc -O -parse-as-library Shared/Models.swift Shared/GTFS.swift Shared/PreparedTransitFeed.swift Shared/TransitFeedStore.swift OCTranspo/RoutingSchedule.swift OCTranspo/RoutingIndex.swift Tests/TransitSpeedTests.swift -o "$test_dir/test"
"$test_dir/test"
