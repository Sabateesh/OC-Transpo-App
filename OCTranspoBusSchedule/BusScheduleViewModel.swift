//V1 Number Not working but arrival time is.
 //BusScheduleViewModel
 import Combine
 import Foundation
 import SwiftUI
 import MapKit
 import CoreLocation
 import UIKit

 class BusScheduleViewModel: ObservableObject {
     @Published var busSchedules: [String: [BusSchedule]] = [:]
     private var cancellables = Set<AnyCancellable>()
     @Published var isPresentingHomeView = false
     @Published var isBusScheduleFetched: Bool = false


     func fetchBusSchedules(stopNumber: String, completion: @escaping (Result<String, Error>) -> Void) {
         let apiKey = "be504de1abdc88e8ba10d4d7e2f12830"
         let appId = "274ad2e6"
         let urlString = "https://api.octranspo1.com/v2.0/GetNextTripsForStop?appID=\(appId)&apiKey=\(apiKey)&stopNo=\(stopNumber)&format=json"

         guard let url = URL(string: urlString) else {
             print("Invalid URL")
             return
         }

         URLSession.shared.dataTask(with: url) { data, response, error in
             guard let data = data, error == nil else {
                 print("Error fetching bus schedules: \(error?.localizedDescription ?? "Unknown error")")
                 return
             }

             do {
                 let decoder = JSONDecoder()
                 let response = try decoder.decode(OCResponse.self, from: data)

                 let fetchedSchedules = response.getBusSchedules()
                 let stopLabel = response.GetNextTripsForStopResult.StopLabel
                 DispatchQueue.main.async {
                     self.busSchedules = fetchedSchedules
                     completion(.success(stopLabel))
                 }
             } catch {
                 print("Error decoding bus schedules: \(error.localizedDescription)")
                 completion(.failure(error))
             }
             DispatchQueue.main.async {
                 self.isBusScheduleFetched = true
             }
         }.resume()
     }
 }


 struct OCResponse: Codable {
     let GetNextTripsForStopResult: GetNextTripsForStopResult
 }

 struct GetNextTripsForStopResult: Codable {
     let StopNo, StopLabel, Error: String
     let Route: Route
 }

 struct Route: Codable {
     let RouteDirection: [RouteDirection]
 }

 struct RouteDirection: Codable {
     let RouteNo, RouteLabel, Direction, Error, RequestProcessingTime: String
     let Trips: Trips
 }

 struct Trips: Codable {
     let Trip: [Trip]
 }

 struct Trip: Codable {
     let RouteNo, TripDestination, AdjustedScheduleTime, StopNo, BusType, Longitude, Latitude: String?
 }

 extension OCResponse {
     func getBusSchedules() -> [String: [BusSchedule]] {
         let routeDirections = GetNextTripsForStopResult.Route.RouteDirection
         var busSchedules: [String: [BusSchedule]] = [:]

         for routeDirection in routeDirections {
             let routeNo = routeDirection.RouteNo
             let trips = routeDirection.Trips.Trip

             for trip in trips {
                 let schedule = BusSchedule(
                     routeNo: routeNo,
                     destination: trip.TripDestination ?? "N/A",
                     arrivalTime: trip.AdjustedScheduleTime ?? "N/A",
                     BusType: trip.BusType ?? "Unknown",
                     Longitude: trip.Longitude ?? "Unknown",
                     Latitude: trip.Latitude ?? "Unknown"
                 )
                 
                 if var existingSchedules = busSchedules[routeNo] {
                     existingSchedules.append(schedule)
                     busSchedules[routeNo] = existingSchedules
                 } else {
                     busSchedules[routeNo] = [schedule]
                 }
             }
         }
         return busSchedules
     }
 }

