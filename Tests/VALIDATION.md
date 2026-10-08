# Trip planner validation

## 2026-10-07 — Map and Alerts UI

- Map has a compact All/Stops/Vehicles layer switcher, larger stop tap targets, a blue current-location marker, and a zoom hint. Stops appear when zoomed in enough to avoid a crowded default view. Extra map points of interest are hidden, while route-number vehicle markers remain visible. The hint yields to the active-journey bar.
- Alerts has route/stop/title search, All and Pinned routes filters, a visible alert count and last-check time, clearer alert cards, and distinct empty and failed-feed states. Tapping a card still opens the agency alert.
- The iPhone 17 simulator Debug build launched directly into each tab for visual checks in dark and light appearances. The final Release iOS Simulator app and widget built without compiler warnings. These changes affect presentation and filtering; routing tests were not rerun.

## 2026-10-07 — Home and trip UI cleanup

- Home now leads with destination search and Home/Work, followed by a compact nearby map and departure cards. Search focus hides the map and shortcuts to leave room for results. The map also stays hidden when location is unavailable or accessibility text sizes need the space.
- Nearby lines, search suggestions, saved stops, stop details and service alerts use consistent spacing and card backgrounds. Alerts has a clear empty state. Planner fields and journey choices group times, transfers and route badges more clearly; selectable departures use full-width rows. The journey guide keeps its primary action and uses the same card styling.
- The final Release iOS Simulator app and widget built without compiler warnings. The app installed and launched on the iPhone 17 simulator with Ottawa location. Home was visually checked in dark and light appearances: `Tests/Evidence/2026-10-07-clean-home-dark.png` and `Tests/Evidence/2026-10-07-clean-home-light.png`. This was a view-only change, so the routing test suites were not rerun.

## 2026-10-07 — Selectable departures and line-based journey guidance

- Journey cards and active guidance can switch a selected leg to another departure on the same line. The selector updates later connections and arrival time, excludes missed or cancelled trips, and shows a countdown and transfer warning. The active session keeps its current step when switching a future leg.
- Live line details can start guidance toward any later stop, including an already-on-board start. The selected boarding stop must still be ahead when starting from a nearby line; otherwise GO asks the rider to choose another departure or confirm that they are aboard. Searching for another trip from this guide opens the destination planner.
- Journey settings now include spoken leaving, boarding, last-two-stops and get-off prompts, a headphones-only choice, and adjustable leave, transfer and get-off notifications. A transfer notification identifies the next line; simultaneous transfer/get-off reminders are combined.
- Confirmed stop-closure alerts remove affected boarding and alighting choices. Planner, line and guide maps mark closed and alternative stops and distinguish the scheduled shape with a dashed line. The relevant alert shows the agency's published detour map when supplied. OC Transpo's alert feed does not publish a georeferenced temporary path, so the app does not draw an inferred path on the map.
- Pinned nearby routes move above other departures on Home. Departure cards show crowding only for a fresh vehicle occupancy field. The public feed sampled during development supplied no occupancy values, so the label remains hidden for those vehicles.

### Verification and limits

- `bash Tests/run-journey-tests.sh`: **50 passed**. `bash Tests/run-journey-search-tests.sh`: **10 passed**. `bash Tests/run-journey-features-tests.sh`: **132 passed**. `bash Tests/run-transit-speed-tests.sh`: **17 passed**. Total: **209 deterministic scenarios**.
- The Release iOS Simulator app and widget built without compiler warnings. The app installed and launched on the iPhone 17 simulator with an Ottawa location; the Home map and nearby live departure cards rendered. The screenshot is `Tests/Evidence/2026-10-07-release-home.png`.
- A live vehicle-feed sample had 543 vehicles, 534 fresh, and no occupancy values. Crowding cannot be shown reliably until the agency supplies it. Departure selection, spoken audio delivery, notification timing, and published detour images were covered by code/build checks but were not interactively exercised on a physical ride. Locked-screen audio and battery impact remain unverified on a phone.

## 2026-10-06 — Timetable coverage, accessibility, alerts, transfers and journey measurement

- The bundled timetable was regenerated from the current public GTFS feed. It contains 109,595 prepared trip templates and published service through October 25, 2026. The daily GitHub Actions refresh validates that the source covers at least 14 more days before replacing the bundle, then opens or updates a timetable pull request. If the agency has not published enough service, the job fails and preserves the existing resource. This workflow starts after these files are published to the repository's default branch; its pull-request step requires the repository setting that permits Actions to create pull requests.
- Planning for a date beyond both the bundled and downloaded feeds reports the final covered day and offers a download retry. Home displays a coverage warning within 14 days of the end date.
- Trip and stop wheelchair fields from GTFS survive preparation, routing, and journey restoration. The wheelchair-vehicle filter requires an explicitly accessible trip and rejects explicitly inaccessible boarding or alighting stops. Unknown stop access and unverified walking paths stay labelled unknown.
- Alert matching checks affected routes, listed stops, direction and effective dates. Published start and end hours and nightly operating hours are applied where the text is parseable. Broad route-only notices and notices with unverified dates are labelled possible.
- Trip cards and active guidance show each transfer's available time, estimated walk, boarding buffer and remaining margin. A late arrival that removes the buffer is flagged as missed and triggers the existing replacement search.
- The Debug journey settings can start or stop a measurement and export JSON reports. The recorder keeps its log across app relaunches and records GPS update age/accuracy, background state, live-feed success, Live Activity update requests and battery level without coordinates. Use a physical phone for a full locked-screen ride: enable the measurement, lock the phone, complete the journey, then export both files. Check notification delivery and compare the starting/ending battery levels with the phone unplugged.

### Verification and limits

- The refreshed prepared bundle passed packed-feed validation; the public feed still ends October 25. The refresh job cannot create service beyond what the agency publishes.
- Final checks: 46 scheduled-routing, 10 asynchronous-search, 118 journey-feature and 17 feed/cache scenarios passed. The Release iOS Simulator app and widget built without compiler warnings.
- Simulator-only journey evidence is in `Tests/Evidence/2026-10-06-simulator-journey-summary.json` and `Tests/Evidence/2026-10-06-simulator-journey-events.jsonl`. During a 56-second test, the app received 9 location updates in the background, completed 2 live refreshes, and resumed its measurement after one relaunch. The simulator returned battery level -1, so energy use could not be measured.
- The iPhone 15 Pro remained unavailable and the user requested simulator checks for now. Locked physical-phone operation, real-ride notification delivery and battery impact remain unverified.

## 2026-10-04 — Location recovery, trip alerts, offline guidance and Live Activity actions

### Changes

- Location has explicit locating, ready, denied, restricted and unavailable states. A 15-second timeout exposes retry; denied access exposes Settings. Home and the planner offer a starting-address picker. Stale or inaccurate GPS fixes are rejected.
- Trip cards and active guidance match RSS alerts against route names, boarding/alighting stops and intermediate calling points. Completed journey legs are excluded. The parser now handles the live feed's comma-separated route categories. Alerts refresh at most every five minutes, retain the previous snapshot on HTTP/XML failure and label saved data. RSS alerts may describe future work or one direction; users are prompted to check dates and details, and the planner does not infer closures from prose.
- Trip and journey screens distinguish live predictions, last known predictions and scheduled times, and show when the live feed was last received. Active journeys retain the latest received predictions when updates stop. Apple Maps walking instructions and path coordinates are saved in the active journey archive; missing instructions can be fetched without blocking guidance. Older archives remain readable.
- Lock Screen and expanded Dynamic Island views include boarding/alighting App Intent buttons. Intents run in the app, require authentication and validate session ID, leg index, current boarding state, expiry and a persisted single-use action token. Duplicates and buttons from previous steps/journeys cannot advance progress. Final walking stages have no boarding button.

### Verification

- `bash Tests/run-journey-tests.sh`: **40 passed**.
- `bash Tests/run-journey-search-tests.sh`: **10 passed**.
- `bash Tests/run-journey-features-tests.sh`: **98 passed**, including walking instructions and metadata round trips, legacy archive compatibility, RSS parsing/matching, prediction labels and action validation.
- `bash Tests/run-transit-speed-tests.sh`: **17 passed**. Total: **165 deterministic scenarios**.
- Final Debug and Release simulator builds succeeded without compiler warnings for the app and widget. Standalone macOS test builds retain existing MapKit deprecation warnings for APIs needed by the iOS 17 deployment target.
- The public RSS endpoint returned HTTP 200 with 24 items. Its actual multi-route category format (`affectedRoutes-61, 62, 63`) is now covered by a regression test.
- On the iPhone 17 / iOS 26.2 simulator, revoked location permission reported denied/no location. Granting permission and supplying Ottawa coordinates reported ready/has location. The denied-access screen was visually inspected.
- A controlled Core Location provider verified locating, timeout to unavailable, retry, stale-fix rejection, successful recovery and cancellation of the timeout after recovery. Simulator clearing of location alone continued to return a cached fix, so it was not counted as timeout evidence.
- Actual App Intent `perform()` calls in the simulator verified boarding, transfer boarding, alighting, final walk, persistence, duplicate rejection and rejection after ending the journey. Relaunch restored an onboard journey with **14 Apple Maps walking instructions**, and its saved alighting action advanced exactly one leg. Reports are in `Tests/Evidence/2026-10-04-*.json`.
- The restored transfer screen was visually checked for the saved walking-directions control and scheduled-time/feed-age labels.

### Limits and reproduction

Physical locked-phone authentication, actual widget button taps, real-ride GPS and VoiceOver/Dynamic Type interaction were not verified. Simulator intent calls exercise the handler but do not prove the system authentication UI. Offline restoration is covered by disk round-trip tests; airplane-mode radio behavior was not tested on a device. Walking directions are available offline only after they have been fetched and saved; the UI identifies missing written directions.

Debug diagnostics use an isolated archive under `Documents/journey-diagnostics`: `--journey-diagnostics --actions`, `--journey-diagnostics --location-retry`, or `--journey-diagnostics --start` followed by a relaunch with `--journey-diagnostics --resume-action`. End with `--journey-diagnostics --end`. Production builds exclude these checks.


## Shared timetable and faster searches — 2026-10-03

Implemented all six speed changes:

- Home and the planner consume one `TransitFeedStore` actor, prepared feed and cache. Concurrent network checks/downloads coalesce; the widget reads a small summary in the same cache directory. Matching legacy caches reuse the bundle instead of parsing raw CSV again.
- `RoutingStore` caches prepared networks by feed version and service date. Immutable stop grids and transfer distances are shared across dates; departure indexes restrict each routing round to trips reachable from its current stops. Feed updates invalidate the networks. Live delays use conservative candidate selection so delayed trips are not pruned using scheduled times.
- The app includes `BundledTimetable.transit`: 6,514,018 bytes (6.2 MiB), 68,408 trip templates, service September 25–October 25, 2026. Packed stop calls preserve times, sequences, boarding restrictions, shape distances, calendars and exceptions. A version file identifies matching downloads.
- Usable cached schedules return immediately while stale data refreshes. Atomic prepared snapshots survive failed downloads. Expired bundles are rejected; a newer valid bundle can replace an expired downloaded cache. The bundle is a startup fallback, and new feeds refresh in the background.
- The 20-second display refresh applies predictions and removes unavailable trips. Full searches run for expired/cancelled connections, missed transfers, changed inputs, a new timetable, changes in live-feed availability, or a two-minute check for better alternatives. Countdown rendering does not run the router.
- Destination search reuses its autocomplete object, waits 150 ms after typing before sending a query, shows matching Home/Work/recent destinations immediately, retains matching suggestions and caches up to 40 query results by area. Cancelled queries cannot replace explicit address searches.

### Validation

- 40 routing, 10 asynchronous search, 72 journey/destination feature, and 17 feed/cache/index scenarios passed: 139 total.
- Debug and optimized simulator builds succeeded. The production Release app and widget also built successfully. The standalone macOS test compiler reports MapKit deprecations for APIs retained for iOS 17 compatibility.
- Compared the old and indexed routers on four real Ottawa journeys in both depart-at and arrive-by modes: all 135 route identities and their order matched. Departure/arrival estimates differed by at most 0.141 seconds. Before/after route reports are in `Tests/Evidence/2026-10-03-routes-*.json`.
- Live autocomplete returned the expected results for `car`, `ride`, `alg`, and `100 que`. Public GTFS plus Apple Maps returned address-to-address journeys, verified walking legs, real shapes for 12 transit legs, and five valid arrive-by choices. Four additional Ottawa-area journeys returned routes.
- The standalone live check deliberately has no bundled resource: its empty-cache download/preparation took 9.02 seconds to first routes; a repeat took 0.21 seconds and completed walking refinement at 0.65 seconds. The shipped app uses the prepared bundle when its calendar covers the requested date.

### Optimized simulator comparison

Same iPhone 17 Pro simulator, Release optimization with Debug benchmark entry points enabled, same fixed downtown → Algonquin request for October 2 at 08:00. Each cold run used an empty dedicated benchmark cache. Before downloaded the timetable; after used the bundled prepared timetable and checked for updates independently. Walking refinement was stubbed for this first-route measurement. Every stage returned five options.

| First provisional route | Before | After |
| --- | ---: | ---: |
| Empty app timetable cache | 3.40 s | 0.82 s |
| Repeat 1 | 0.306 s | 0.294 s |
| Repeat 2 | 0.305 s | 0.294 s |
| Reopen from disk | 0.763 s | 0.745 s |

The cold run improved about 76%. These are single-run simulator observations, not physical-iPhone guarantees. Earlier Debug timings in this document used different optimization settings and should not be compared directly. Raw results are in `Tests/Evidence/2026-10-03-planner-*.json`.

### Keep the bundled timetable current

Run `bash Tests/prepare-bundled-timetable.sh /path/to/extracted/GTFS` before shipping an updated bundle. It writes the app resource and matching CRC version file, validates its packed representation, and prints its service window and size. The binary must be regenerated from the full public feed, including calendar exceptions; do not extend its expiry date manually. Both resources are included through Xcode's synchronized app group. A build released after October 25 needs a newer bundle for the fast offline first-run path; the network fallback remains available.

Run `bash Tests/run-transit-speed-tests.sh` for shared downloads, stale-cache return, expiry, refresh failure, corrupted-cache fallback, migration and index reuse. Existing routing, search and feature scripts cover route correctness and the refreshed UI data. Physical-device launch profiling remains deferred at the user's request.

## Background journeys, recovery and startup — 2026-10-02

Implemented background location for active journeys, Lock Screen/Dynamic Island guidance, saved journey restoration, automatic replacement searches, and conservative boarding detection. Replacements preserve an onboard leg and are rechecked against current predictions, cancellations, skipped stops and transfer buffers before switching. Reminder and automatic boarding preferences persist. Ending or completing a journey stops tracking, clears the archive and removes its Live Activity.

### Validation

- 40 routing scenarios, 8 asynchronous search/cache scenarios, and 68 journey feature scenarios passed (116 total).
- Debug and Release simulator builds succeeded without compiler warnings, including the Live Activity widget. Production Info.plist contains location background mode and Live Activity support; diagnostic launch modes are Debug only.
- On the iPhone 17 Pro simulator, starting a journey created one Live Activity and an onboard archive. Relaunch restored the destination, onboard state and step with one activity. Ending removed the archive and activity. JSON reports are in `Tests/Evidence`.
- While Settings was foreground, injected route locations reached the journey location delegate, updated persisted stop progress and triggered ActivityKit content updates. This checks background execution in the simulator.
- Inspected the restored guidance layout through simulator screenshots. Activity creation and updates were checked through ActivityKit state/logs; full Lock Screen layout and notification delivery still need physical-device testing.
- Boarding tests require sustained accurate movement on the published route, a matching service date, and a nearby, fresh, moving vehicle. Walking, stale vehicles, a different trip/day, missing route geometry and off-route movement retain manual confirmation.
- Physical iPhone measurements were deferred at the user's request. A real ride, prolonged locked-screen operation, battery use and notification delivery remain unverified. iOS can suspend or terminate the app; force-quitting stops background tracking until reopening. Stale Live Activities ask the rider to open the app for updates.

### Simulator performance

Debug build, iPhone 17 Pro simulator, October 2 at 08:00 Ottawa time, downtown (45.4215, -75.6972) to Algonquin (45.3488, -75.7549). Each cold run used its own empty benchmark cache and downloaded the public timetable. The benchmark measures first provisional routes; walking refinement is stubbed and is not part of these numbers. Five options were returned in every stage.

| First route | Before | After |
| --- | ---: | ---: |
| Empty cache, including timetable download | 10.59 s | 8.06 s |
| Repeat 1, timetable in memory | 1.31 s | 1.26 s |
| Repeat 2, timetable in memory | 1.31 s | 1.27 s |
| Reopen from compiled disk cache | 1.82 s | 1.74 s |

The loader downloads independent timetable files concurrently and returns the parsed timetable before encoding/writing the cache on a utility task. Cache writes are serialized, and subsequent date loads wait for pending writes. The cold comparison improved about 24% in these two runs; network variability and simulator hardware prevent treating that as a phone performance guarantee. Raw measurements are saved in `Tests/Evidence/simulator-planner-*.json`.

### Reproduce simulator checks

Build/install the Debug app, then launch with `--planner-benchmark`. Results are written under the app data container at `Documents/planner-benchmark/results.json`. Archive that dedicated benchmark cache before another cold run; do not remove the app's normal timetable cache. The fixed benchmark date requires a public feed covering October 2, 2026; update it for later timetables.

For lifecycle checks, use `--journey-diagnostics --start`, relaunch with `--journey-diagnostics`, then launch with `--journey-diagnostics --end`. Reports and the isolated journey archive live in `Documents/journey-diagnostics`. Grant simulator location access before background-location checks. These diagnostic modes create a real Live Activity and use an isolated archive, so run them on a test simulator. Normal journey state is restored only on a normal launch.

The sections below are historical validation records; their former foreground-only guidance limitations are superseded by this implementation.

## Transit-style journey companion — 2026-10-01

The guide now uses a map-first screen, a prominent next action, arrival summary, stop countdown, waiting-at-stop detection, stop-by-stop timeline, transfer card, optional leave/get-off reminders, and a persistent journey bar. It follows the main guidance patterns described in [Transit's GO documentation](https://help.transitapp.com/article/549-how-to-use-go).

- `bash Tests/run-journey-features-tests.sh`: **39 scenarios passed**. Added phase changes, stale GPS rejection, monotonic stop progress, estimates after GPS becomes stale, leave/get-off reminder timing, reminder cleanup between stages, and preventing premature get-off prompts when recent GPS shows earlier stops.
- iOS Simulator Debug build succeeded without compiler warnings. The macOS test compiler reports deprecations for MapKit APIs retained for iOS 17 compatibility.
- Deterministic Debug previews were used to inspect walking, riding, get-off, expanded timeline, and minimized journey layouts. Screenshots exposed missing secondary text in the material panel, an overlapping map control, and tab-bar overlap; these were corrected. Final checks confirmed the journey bar above the tab controls and readable get-off guidance in light and dark appearances. The simulator was restored to dark appearance and a normal app launch. The preview uses sample trip times and is labelled Preview; it is excluded from Release builds.
- Reminder timing is unit-tested, but notification permission dialogs, delivery on a locked physical phone, location during a real ride, and touch interactions are not yet verified. Computer-use access to Device Hub still times out; simulator rendering was inspected through the Apple simulator screenshot command.
- Confirm boarding and alighting manually. GPS confirms progress near stops while the app is active. Local reminders can fire in the background using the last available times. Continuous background GPS, automatic boarding, voice guidance, Live Activities, and crowdsourcing are not included.

## Complete journey features — 2026-10-01

Implemented saved Home/Work destinations, active-screen departure refresh, cancellation and delay notices, route preference labels and countdowns, arrive-by search, and an interactive journey guide with published bus/rail paths.

### Automated checks

- `bash Tests/run-journey-tests.sh`: **40 scenarios passed**. New cases cover latest feasible arrive-by departure, exact deadlines, transfer direction, delays and cancellations at a deadline, past deadlines, delay amounts, and stable journey identity.
- `bash Tests/run-journey-search-tests.sh`: **6 scenarios passed**. Controlled walking requests verify progressive results and cancellation isolation; refresh tests check canceled/expired route removal, notices, and arrive-by refinement.
- `bash Tests/run-journey-features-tests.sh`: **23 scenarios passed**. Covers Home/Work persistence/removal, labels and countdowns, walking feasibility, shape clipping and missing-distance rail paths, guidance progression, stale GPS rejection, propagated predictions, service dates, and skipped stops.
- iOS Simulator Debug build succeeded without compiler warnings. Installed and launched on the booted iPhone simulator.

### Live service check

`bash Tests/run-live-planner-check.sh` passed using the public OC Transpo timetable and Apple Maps for October 1 at 08:00 Ottawa time:

- Short-prefix searches `car`, `ride`, `alg`, and `100 que` returned the expected destinations.
- 100 Queen Street → 1385 Woodroffe Avenue returned five choices, beginning with Line 1 → bus 75. All walking legs on that first choice were verified; some other choices retained explicitly labelled walking estimates.
- All **11 transit legs** across those choices loaded actual published geometry (64–708 points per leg). The check exposed blank distance fields in Line 1 shapes; ordered stop matching now handles them.
- **Five arrive-by options** reached the destination by 09:30 after walking refinement. The latest suggested leave time was 08:35:55. All arrive-by legs also loaded real shapes.
- Rideau → Carleton, Bayshore → downtown, Barrhaven → Algonquin, and Kanata → Ottawa Hospital all returned routes.
- On this Mac, an empty timetable cache showed first routes in **9.90 s**, and a repeat search in **0.95 s**; refinement completed at 11.67 s and 2.48 s respectively. The four additional routing calculations took 0.52–0.71 s. These measurements are not phone performance guarantees.

### Limits

Visual interaction testing remains unverified because the computer-use connection to Device Hub timed out. No physical ride was tested. Realtime changes were tested with deterministic GTFS-RT fixtures; live checks used the public timetable and Apple Maps. Guidance requires the screen to remain open and manual boarding/alighting confirmation. Shapes describe scheduled paths, not live detours. Missing shapes show stop markers; coverage remains OC Transpo only.

## Earlier validation — 2026-09-30

## Automated checks

- `bash Tests/run-journey-tests.sh`: 27 scenarios passed, including scheduled routes, transfers between different stops, calendar exceptions, overnight service, next-day departures, walking limits, live delays, cancellations, skipped stops, concurrent date requests, and cache recovery.
- Xcode Debug build for iOS Simulator: succeeded with no compiler warnings.
- `bash Tests/run-live-planner-check.sh`: passed against public OC Transpo GTFS and Apple Maps.

## Live service checks

At an Ottawa departure time of 08:00 on September 30:

| Search | Result |
| --- | --- |
| `car` | Carleton University |
| `ride` | Rideau Centre |
| `alg` | Algonquin College |
| `100 que` | 100 Queen St, Ottawa |

100 Queen Street → 1385 Woodroffe Avenue returned five route combinations. The first was Line 1 → bus 75, with all three walking segments verified by Apple Maps. The full first-run check took about 15 seconds, including timetable preparation and walking requests.

Timetable-only checks found routes for Rideau → Carleton (1 → 2), Bayshore → downtown (58 → 1), Barrhaven → Algonquin (75), and Kanata → Ottawa Hospital (67 → 1 → 45). The final test build searched each in about 1.1–1.4 seconds on this Mac. These are test observations, not performance guarantees for phones or future service dates.

## Remaining validation limits

The simulator build was installed and launched. Visual interaction testing could not be completed because the computer-use tool timed out on Device Hub. Tests used live place search and walking services, plus the published timetable; realtime overlays were validated with deterministic GTFS-RT fixtures, not an on-device journey. Coverage is OC Transpo, not STO. At this earlier stage transit polylines connected stops; the October 1 implementation above replaces them with published route shapes.

## Planning speed fix — 2026-09-30

Routes are published after the first timetable search. Walking checks run afterward with up to three concurrent requests and a five-second timeout per request. Checked walking routes are cached across searches; provisional walks stay labelled as estimates and inaccessible connections are removed when checks finish. The timetable starts preparing when the app opens.

Measured on the same Mac and Ottawa feed (not phone performance guarantees):

| Work | Before | After |
| --- | ---: | ---: |
| Queen Street → Woodroffe routing calculation, optimized build | 1.17 s | 0.48 s |
| Other three benchmark routing calculations | 1.03–1.29 s | 0.41–0.54 s |
| Timetable cache decode | 2.77 s | 0.86 s |
| Timetable cache size | 95 MB | 40 MB |
| First timetable CSV parse, unoptimized/debug build | 37.80 s | 10.21 s |

The optimized router returned the same ordered options for all four benchmark journeys. The faster CSV reader produced a timetable equal to the original in every stop, route, trip, call, and service date. Quoted CSV and reordered columns retain the normal parser as a fallback.

Validation: 30 scheduled-routing tests and three progressive-display scenarios passed. The latter hold walking requests open to prove routes are already visible, then verify connection removal and cancellation behavior. The final iOS Simulator build succeeded. A first installation still needs the timetable download; later searches reuse it.

Final live address test: first routes appeared in 8.67 seconds with an empty cache, including download and timetable preparation; walking refinement finished at 9.88 seconds. Repeating the same search showed routes in 0.50 seconds and finished refinement at 1.44 seconds. All suggested walking legs were verified in that test. The simulator build was installed and launched.
