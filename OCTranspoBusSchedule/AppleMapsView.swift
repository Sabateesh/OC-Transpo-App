
//
//  AppleMapsView.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-12-28.
//
import SwiftUI
import MapKit

struct BusStop: Identifiable {
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
}

struct AppleMapView: View {
    @EnvironmentObject var locationManager: LocationManager
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.4215, longitude: -75.6972),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var busStops: [BusStop] = []
    @State private var selectedBusStop: BusStop?

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, annotationItems: busStops) { busStop in
                MapAnnotation(coordinate: busStop.coordinate) {
                    Button(action: {
                        selectedBusStop = busStop
                        print("Bus stop selected: \(busStop.name)")
                    }) {
                        Image(systemName: "bus")
                            .foregroundColor(.blue)
                    }
                }
            }
            .onAppear {
                updateRegionToUserLocation()
                fetchBusStops()
            }

            if let selectedBusStop = selectedBusStop {
                BusStopInfoView(busStop: selectedBusStop)
                    .position(x: UIScreen.main.bounds.width / 2, y: 150)
            }
        }
    }

    private func updateRegionToUserLocation() {
        if let userLocation = locationManager.userLocation {
            region = MKCoordinateRegion(center: userLocation.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        }
    }

    private func fetchBusStops() {
        let apiKey = "be504de1abdc88e8ba10d4d7e2f12830"
        let appId = "274ad2e6"
        let urlString = "https://api.octranspo1.com/v2.0/Gtfs?appID=\(appId)&apiKey=\(apiKey)&table=stops&format=json"

        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Error fetching bus stops: \(error?.localizedDescription ?? "Unknown error")")
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
                    Text(busStop.name)
                        .font(.headline)
                    Text("Stop Code: \(busStop.code)")
                        .font(.subheadline)
                }
                .padding()
                .background(Color.white)
                .cornerRadius(8)
                .shadow(radius: 3)
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
}
