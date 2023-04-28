//
//  RoutePlannerViewModel.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-04-04.
// BETA FEATURE STILL IN WORKS

import Foundation
import MapKit
import Combine

class RoutePlannerViewModel: ObservableObject {
    @Published var routes: [TransitRoute] = []
    @Published var currentLocation: CLLocation? = nil

    private var cancellables = Set<AnyCancellable>()
    
    func fetchRoutes(startingLocation: String, destination: String) {
        let apiKey = "AIzaSyDvkCg1wd25wgt1vgnUP9tMOWkaIVvlOSY"
        let encodedStartingLocation = startingLocation.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedDestination = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://maps.googleapis.com/maps/api/directions/json?origin=\(encodedStartingLocation)&destination=\(encodedDestination)&mode=transit&key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Error fetching routes: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            // Print raw JSON response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("JSON String: \(jsonString)")
            }
            
            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(GoogleDirectionsResponse.self, from: data)
                let routes = response.routes.map { $0.toTransitRoute() }
                DispatchQueue.main.async {
                    self.routes = routes
                }
            } catch {
                print("Error decoding routes: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    func setUserLocation(_ location: CLLocation?) {
        self.currentLocation = location
    }
    
    
    
    
}

struct GoogleDirectionsResponse: Codable {
    let routes: [GoogleRoute]
}

struct GoogleRoute: Codable {
    let legs: [GoogleLeg]
}

struct GoogleLeg: Codable {
    let steps: [GoogleStep]
}

struct GoogleStep: Codable {
    let polyline: GooglePolyline
}

struct GooglePolyline: Codable {
    let points: String
}
struct TransitRoute: Hashable {
    let polyline: MKPolyline
    let distance: CLLocationDistance
    // Add any other properties you want to include in the TransitRoute
}

extension GoogleRoute {
    func toTransitRoute() -> TransitRoute {
        let combinedCoordinates = self.legs
            .flatMap { $0.steps.map { $0.polyline.points } }
            .compactMap { MKPolyline.decodePolyline($0) }
            .reduce([]) { (result, polyline) -> [CLLocationCoordinate2D] in
                result + polyline
            }
        let combinedPolyline = MKPolyline(coordinates: combinedCoordinates, count: combinedCoordinates.count)
        
        // Calculate distance
        var distance: CLLocationDistance = 0
        for i in 1..<combinedCoordinates.count {
            let start = CLLocation(latitude: combinedCoordinates[i-1].latitude, longitude: combinedCoordinates[i-1].longitude)
            let end = CLLocation(latitude: combinedCoordinates[i].latitude, longitude: combinedCoordinates[i].longitude)
            distance += start.distance(from: end)
        }

        let transitRoute = TransitRoute(polyline: combinedPolyline, distance: distance)
        return transitRoute
    }
}

extension MKPolyline {
    static func decodePolyline(_ encodedPolyline: String) -> [CLLocationCoordinate2D]? {
        guard !encodedPolyline.isEmpty else {
            return nil
        }
        
        var index = encodedPolyline.startIndex
        var coordinates: [CLLocationCoordinate2D] = []
        
        var latitude: CLLocationDegrees = 0
        var longitude: CLLocationDegrees = 0
        
        while index != encodedPolyline.endIndex {
            let (nextLatitude, newIndex) = decodePolylineComponent(encodedPolyline, index: index, value: latitude)
            latitude = nextLatitude
            index = newIndex
            
            let (nextLongitude, newIndex2) = decodePolylineComponent(encodedPolyline, index: index, value: longitude)
            longitude = nextLongitude
            index = newIndex2
            
            let coordinate = CLLocationCoordinate2D(latitude: latitude / 1e5, longitude: longitude / 1e5)
            coordinates.append(coordinate)
        }
        return coordinates
    }
    private static func decodePolylineComponent(_ encodedPolyline: String, index: String.Index, value: CLLocationDegrees) -> (CLLocationDegrees, String.Index) {
        var currentIndex = index
        var component: Int64 = 0 // Change from Int to Int64
        var shift = 0
        
        while true {
            let character = encodedPolyline[currentIndex]
            let byte = character.asciiValue! - 63
            component |= Int64(byte & 0x1F) << shift // Cast to Int64
            shift += 5
            currentIndex = encodedPolyline.index(after: currentIndex)
            
            if byte < 0x20 {
                break
            }
        }
        
        let newValue = (component & 1 != 0 ? ~(component >> 1) : component >> 1) + Int64(value * 1e5) // Cast to Int64
        return (CLLocationDegrees(newValue), currentIndex)
    }
}

