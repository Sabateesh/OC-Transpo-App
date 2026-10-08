#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/octranspo-features-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
printf '%s\n' 'enum Secrets { static let octranspoKey = "" }' > "$test_dir/Secrets.swift"
swiftc -O -parse-as-library -module-cache-path "$test_dir/modules" \
    Shared/Models.swift Shared/GTFS.swift Shared/PreparedTransitFeed.swift Shared/TransitFeedStore.swift Shared/Realtime.swift "$test_dir/Secrets.swift" \
    OCTranspo/RoutingSchedule.swift OCTranspo/RoutingIndex.swift OCTranspo/JourneyPlanner.swift OCTranspo/JourneyConnection.swift OCTranspo/JourneyAccessibility.swift OCTranspo/JourneyPresentation.swift \
    OCTranspo/DestinationSearch.swift OCTranspo/SavedDestinations.swift OCTranspo/RouteShapes.swift \
    OCTranspo/ServiceAlert.swift OCTranspo/PredictionStatus.swift OCTranspo/JourneyActionValidation.swift OCTranspo/JourneyArchive.swift OCTranspo/BoardingDetector.swift OCTranspo/JourneyRecovery.swift OCTranspo/JourneyCompanion.swift OCTranspo/JourneyGuidance.swift OCTranspo/JourneyQuickStart.swift Tests/JourneyFeaturesTests.swift -o "$test_dir/features-tests"
"$test_dir/features-tests"
