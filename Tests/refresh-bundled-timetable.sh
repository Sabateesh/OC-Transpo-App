#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
working=$(mktemp -d /tmp/oc-timetable-refresh.XXXXXX)
trap 'rm -rf "$working"' EXIT
curl --fail --location --silent --show-error --retry 3 --max-time 120 \
    https://oct-gtfs-emasagcnfmcgeham.z01.azurefd.net/public-access/GTFSExport.zip \
    --output "$working/feed.zip"
for name in stops routes trips stop_times calendar calendar_dates; do
    unzip -p "$working/feed.zip" "$name.txt" > "$working/$name.txt"
done
python3 - "$working" <<'PYTHON'
import csv, datetime, pathlib, sys
folder = pathlib.Path(sys.argv[1])
dates = []
with (folder/'calendar.txt').open(newline='') as f:
    dates += [row['end_date'] for row in csv.DictReader(f)]
with (folder/'calendar_dates.txt').open(newline='') as f:
    dates += [row['date'] for row in csv.DictReader(f) if row['exception_type'] == '1']
if not dates:
    raise SystemExit('Public GTFS has no dated service')
latest = datetime.datetime.strptime(max(dates), '%Y%m%d').date()
required = datetime.datetime.now(datetime.timezone.utc).date() + datetime.timedelta(days=14)
print(f'Published service through {latest}; required through {required}')
if latest < required:
    raise SystemExit('Published GTFS ends within 14 days; keep the existing bundle and investigate the source feed')
PYTHON
bash Tests/prepare-bundled-timetable.sh "$working" "$working/BundledTimetable.transit"
cp "$working/BundledTimetable.transit" OCTranspo/BundledTimetable.transit
cp "$working/BundledTimetable.version" OCTranspo/BundledTimetable.version
