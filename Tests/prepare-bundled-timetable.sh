#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/oc-prepare.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swiftc -O -parse-as-library Shared/Models.swift Shared/GTFS.swift Shared/PreparedTransitFeed.swift Tests/PrepareBundledTimetable.swift -o "$test_dir/prepare"
"$test_dir/prepare" "$1" "${2:-OCTranspo/BundledTimetable.transit}"
python3 - "$1" "${2:-OCTranspo/BundledTimetable.transit}" <<'PYTHON'
import pathlib, sys, zlib
source = pathlib.Path(sys.argv[1])
names = ["stops.txt", "routes.txt", "trips.txt", "stop_times.txt", "calendar.txt", "calendar_dates.txt"]
version = "|".join(f"{name}:{zlib.crc32((source/name).read_bytes())}" for name in names if (source/name).exists())
pathlib.Path(sys.argv[2]).with_suffix(".version").write_text(version)
PYTHON
