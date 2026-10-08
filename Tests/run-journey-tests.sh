#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/octranspo-journey-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
printf '%s\n' 'enum Secrets { static let octranspoKey = "" }' > "$test_dir/Secrets.swift"
swiftc -O -module-cache-path "$test_dir/modules" Shared/Models.swift Shared/GTFS.swift Shared/PreparedTransitFeed.swift Shared/TransitFeedStore.swift Shared/Realtime.swift \
    "$test_dir/Secrets.swift" OCTranspo/RoutingSchedule.swift OCTranspo/RoutingIndex.swift OCTranspo/JourneyPlanner.swift OCTranspo/JourneyDepartures.swift OCTranspo/JourneyConnection.swift OCTranspo/JourneyAccessibility.swift OCTranspo/JourneyPresentation.swift Tests/JourneyPlannerTests.swift \
    -o "$test_dir/journey-tests"
"$test_dir/journey-tests"
