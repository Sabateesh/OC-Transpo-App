#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/octranspo-live-check.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
printf '%s\n' 'enum Secrets { static let octranspoKey = "" }' > "$test_dir/Secrets.swift"
swiftc -O -parse-as-library -module-cache-path "$test_dir/modules" \
    Shared/Models.swift Shared/GTFS.swift Shared/PreparedTransitFeed.swift Shared/TransitFeedStore.swift Shared/Realtime.swift "$test_dir/Secrets.swift" \
    OCTranspo/RoutingSchedule.swift OCTranspo/RoutingIndex.swift OCTranspo/JourneyPlanner.swift OCTranspo/WalkingRoutes.swift OCTranspo/JourneyPresentation.swift OCTranspo/JourneySearch.swift OCTranspo/JourneyGuidance.swift \
    OCTranspo/RouteShapes.swift OCTranspo/DestinationSearch.swift OCTranspo/SavedDestinations.swift Tests/LivePlannerCheck.swift -o "$test_dir/live-check"
"$test_dir/live-check" "$test_dir/feed"
