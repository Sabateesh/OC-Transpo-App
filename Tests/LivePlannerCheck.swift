import Foundation
import MapKit
@main struct CheckCompleteJourney {
 @MainActor static func main() async throws {
  func place(_ query: String) async throws -> MKMapItem {
   let request = MKLocalSearch.Request()
   request.naturalLanguageQuery = query
   request.region = MKCoordinateRegion(center:.init(latitude:45.4215,longitude:-75.6972),latitudinalMeters:60_000,longitudinalMeters:60_000)
   return try await MKLocalSearch(request:request).start().mapItems.first!
  }
  let autocomplete = DestinationSearch()
  for (query, expected) in [("car", "Carleton"), ("ride", "Rideau"), ("alg", "Algonquin"), ("100 que", "100 Queen")] {
   autocomplete.update(query, near: CLLocation(latitude:45.4215, longitude:-75.6972))
   for _ in 0..<100 {
    try await Task.sleep(for: .milliseconds(100))
    if !autocomplete.loading { break }
   }
   guard autocomplete.suggestions.contains(where: { $0.title.localizedCaseInsensitiveContains(expected) }) else {
    print("Autocomplete failed:", query, autocomplete.error ?? "expected suggestion missing"); exit(1)
   }
   print("Autocomplete passed:", query, "→", autocomplete.suggestions.first!.title)
  }
  let origin = try await place("100 Queen Street, Ottawa")
  let destination = try await place("1385 Woodroffe Avenue, Ottawa")
  print("Origin",origin.name ?? "",origin.placemark.coordinate)
  print("Destination",destination.name ?? "",destination.placemark.coordinate)
  let date = RoutingTimetable.calendar.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!
  let store = RoutingStore(folder:URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true))
  let search = JourneySearch(store:store)
  let start = Date()
  await search.search(origin:origin.placemark.coordinate,destination:destination.placemark.coordinate,departure:date,live:nil)
  print("First routes in", search.firstResultSeconds ?? -1, "seconds")
  print("Finished in",Date().timeIntervalSince(start),"error",search.error ?? "none")
  for journey in search.journeys {
   print(journey.legs.map { $0.route.name }.joined(separator:" → "),"duration",Int(journey.duration/60),"minutes","walks",journey.walks.map { "\(Int($0.duration/60)) min / verified=\($0.verified)" })
  }
  guard !search.journeys.isEmpty else { exit(1) }
  let repeatStart = Date()
  await search.search(origin:origin.placemark.coordinate,destination:destination.placemark.coordinate,departure:date,live:nil)
  guard !search.journeys.isEmpty else { print("Repeat search returned no routes"); exit(1) }
  print("Repeat first routes in",search.firstResultSeconds ?? -1,"seconds; finished in",Date().timeIntervalSince(repeatStart),"seconds")
  let shaped = await RouteShapes.shared.apply(to: search.journeys)
  let legs = shaped.flatMap(\.legs)
  guard !legs.isEmpty && legs.allSatisfy({ $0.followsShape && $0.coordinates.count > 2 }) else {
   print("Missing real transit shape for", legs.filter { !$0.followsShape }.map { $0.route.name }); exit(1)
  }
  print("Real route shapes loaded for", legs.count, "legs; points", legs.map { $0.coordinates.count })
  let deadline = date.addingTimeInterval(90 * 60)
  await search.search(origin:origin.placemark.coordinate,destination:destination.placemark.coordinate,departure:date,live:nil,arriveBy:deadline)
  guard !search.journeys.isEmpty && search.journeys.allSatisfy({ $0.arrival <= deadline && $0.leave >= date }) else {
   print("Arrive-by validation failed", search.error ?? ""); exit(1)
  }
  print("Arrive by 09:30 passed with", search.journeys.count, "options; latest leave", search.journeys[0].leave)
  let shapedArrival = await RouteShapes.shared.apply(to: search.journeys)
  guard shapedArrival.flatMap(\.legs).allSatisfy(\.followsShape) else { print("Arrive-by shapes failed"); exit(1) }
  let table = try await store.load(for: date)
  for (name, a,b,c,d) in [
   ("Rideau–Carleton",45.4251,-75.6903,45.3876,-75.6960),
   ("Bayshore–downtown",45.3480,-75.8050,45.4215,-75.6972),
   ("Barrhaven–Algonquin",45.2690,-75.7490,45.3490,-75.7540),
   ("Kanata–Ottawa Hospital",45.3110,-75.9090,45.4022,-75.6497)
  ] {
   let timer = Date()
   let choices = JourneyPlanner.plan(timetable: table, origin: .init(latitude:a,longitude:b), destination:.init(latitude:c,longitude:d), departure:date)
   guard !choices.isEmpty else { print("Routing failed:",name); exit(1) }
   print(name,choices.first!.legs.map { $0.route.name }.joined(separator:" → "),Date().timeIntervalSince(timer),"seconds")
  }
 }
}
