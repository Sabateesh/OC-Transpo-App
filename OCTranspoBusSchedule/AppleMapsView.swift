//
//  AppleMapsView.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-12-28.
//
import SwiftUI
import MapKit
import CoreLocation

struct BusStop: Identifiable, Equatable, Hashable {
    let id: String
    let code: String
    let name: String
    let coordinate: CLLocationCoordinate2D

    init(id: String, code: String, name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.code = code
        self.name = name
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func ==(lhs: BusStop, rhs: BusStop) -> Bool {
        return lhs.id == rhs.id && lhs.code == rhs.code && lhs.name == rhs.name &&
               lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
    
    // Hashable conformance
       static func === (lhs: BusStop, rhs: BusStop) -> Bool {
           lhs.id == rhs.id
       }

       func hash(into hasher: inout Hasher) {
           hasher.combine(id)
       }
}

struct AppleMapView: View {
    var locationManager: LocationManager
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.4215, longitude: -75.6972),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State public var busStops: [BusStop] = []
    @State private var selectedBusStop: BusStop? // Managed internally



    
    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, annotationItems: busStops) { busStop in
                MapAnnotation(coordinate: busStop.coordinate) {
                    Button(action: {
                        print("Bus stop tapped: \(busStop.name)")
                        selectedBusStop = busStop
                    }) {
                        Image(systemName: "bus").foregroundColor(.blue)
                    }
                }
            }
            .onAppear(perform: fetchBusStops)
            if let selectedStop = selectedBusStop {
                BusStopInfoView(busStop: selectedStop)
                    .position(x: UIScreen.main.bounds.width / 2, y: 150)
                    .transition(.opacity)
            }
        }
    }


    private func updateRegionToUserLocation() {
        if let userLocation = locationManager.userLocation {
            region = MKCoordinateRegion(center: userLocation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        }
    }

    private func fetchBusStops() {
        print("Fetching bus stops...")
        let apiKey = "be504de1abdc88e8ba10d4d7e2f12830"
        let appId = "274ad2e6"
        let urlString = "https://api.octranspo1.com/v2.0/Gtfs?appID=\(appId)&apiKey=\(apiKey)&table=stops&format=json"
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                        print("Error fetching bus stops: \(error.localizedDescription)")
                        return
                    }
            guard let data = data else {
                        print("No data received")
                        return
                    }
            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(GTFSStopsResponse.self, from: data)
                let fetchedStops = response.Gtfs.map { stop -> BusStop in
                    BusStop(id: stop.stop_id,
                            code: stop.stop_code,
                            name: stop.stop_name,
                            latitude: Double(stop.stop_lat) ?? 0.0,
                            longitude: Double(stop.stop_lon) ?? 0.0)
                }
                DispatchQueue.main.async {
                    self.busStops = fetchedStops
                    print("Fetched \(fetchedStops.count) bus stops")
                }
            } catch {
                print("Error decoding bus stops: \(error.localizedDescription)")
            }
        }.resume()
    }
    struct BusStopInfoView: View {
        let busStop: BusStop

        var body: some View {
            VStack {
                Text("Stop Name: \(busStop.name)\nStop Code: \(busStop.code)")
                    .font(.system(size: 13))
                    .foregroundColor(.black)
                    .frame(width: UIScreen.main.bounds.width / 2)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(8)
            .shadow(radius: 3)
            .onAppear {
                print("BusStopInfoView appeared with: \(busStop.name)")
            }
        }
    }


    struct GTFSStopsResponse: Codable {
        let Gtfs: [GTFSStop]
    }

    struct GTFSStop: Codable {
        let stop_id: String
        let stop_code: String
        let stop_name: String
        let stop_lat: String
        let stop_lon: String
    }
    
    
    func findNearestBusStop(completion: @escaping (BusStop?) -> Void) {
        guard let currentLocation = locationManager.userLocation else {
            completion(nil)
            return
        }

            let nearestStop = busStops.min(by: { (stop1, stop2) -> Bool in
                let distance1 = distance(from: currentLocation.coordinate, to: stop1.coordinate)
                let distance2 = distance(from: currentLocation.coordinate, to: stop2.coordinate)
                return distance1 < distance2
            })

            completion(nearestStop)
        }

        private func distance(from coordinate1: CLLocationCoordinate2D, to coordinate2: CLLocationCoordinate2D) -> CLLocationDistance {
            let location1 = CLLocation(latitude: coordinate1.latitude, longitude: coordinate1.longitude)
            let location2 = CLLocation(latitude: coordinate2.latitude, longitude: coordinate2.longitude)
            return location1.distance(from: location2)
        }
}
