/*

import SwiftUI
import GoogleMaps
import SDWebImage

struct BusStop {
    let id: String
    let code: String
    let name: String
    let latitude: Double
    let longitude: Double
}

class MapViewDelegate: NSObject, GMSMapViewDelegate {
    var onMapIdle: ((GMSMapView) -> Void)?

    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        mapView.selectedMarker = marker
        return true
    }

    func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
        onMapIdle?(mapView)
    }
}

struct GoogleMapsView: UIViewRepresentable {
    @EnvironmentObject var locationManager: LocationManager
    private let mapViewDelegate = MapViewDelegate()

    func makeUIView(context: Context) -> GMSMapView {
        let mapView = GMSMapView()

        if let userLocation = locationManager.userLocation {
            let camera = GMSCameraPosition.camera(withLatitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude, zoom: 16)
            mapView.camera = camera
        }

        mapView.isMyLocationEnabled = true
        mapView.delegate = mapViewDelegate
        mapView.mapType = .normal
        mapView.setMinZoom(16, maxZoom: 16.5)

        mapViewDelegate.onMapIdle = { mapView in
            let bounds = GMSCoordinateBounds(region: mapView.projection.visibleRegion())
            self.fetchBusStops(in: bounds) { busStops in
                DispatchQueue.main.async {
                    mapView.clear()
                    self.addBusStopMarkers(busStops, to: mapView)
                }
            }
        }

        return mapView
    }


    func updateUIView(_ mapView: GMSMapView, context: Context) {
        if let userLocation = locationManager.userLocation {
            let camera = GMSCameraPosition.camera(withLatitude: userLocation.coordinate.latitude, longitude: userLocation.coordinate.longitude, zoom: 16)
            mapView.animate(to: camera)
        }
    }

    private func addBusStopMarkers(_ busStops: [BusStop], to mapView: GMSMapView) {
        for busStop in busStops {
            let symbol = UIImage(systemName: "bus")!
            let resizedImage = resizeImage(symbol, to: CGSize(width: 24, height: 24))

            let imageView = UIImageView(image: resizedImage)
            let imageUrlString = "https://example.com/\(busStop.id).png"
            let imageUrl = URL(string: imageUrlString)
            imageView.sd_setImage(with: imageUrl, placeholderImage: resizedImage, options: [], completed: nil)

            let marker = GMSMarker()
            marker.position = CLLocationCoordinate2D(latitude: busStop.latitude, longitude: busStop.longitude)
            marker.title = busStop.name
            marker.snippet = "Stop ID: \(busStop.code)"
            marker.iconView = imageView
            marker.map = mapView
        }
    }

    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return resizedImage
    }

    func fetchBusStops(in bounds: GMSCoordinateBounds, completion: @escaping ([BusStop]) -> Void) {
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
                let fetchedStops = response.Gtfs.map { stop in
                    BusStop(id: stop.stop_id, code: stop.stop_code, name: stop.stop_name, latitude: Double(stop.stop_lat) ?? 0.0, longitude: Double(stop.stop_lon) ?? 0.0)
                }
                completion(fetchedStops)
            } catch {
                print("Error decoding bus stops: \(error.localizedDescription)")
            }
        }.resume()
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





import SwiftUI
import GoogleMaps
import SDWebImage

class BusStop: NSObject, GMUClusterItem {
    let id: String
    let code: String
    let name: String
    let latitude: Double
    let longitude: Double
    let position: CLLocationCoordinate2D

    init(id: String, code: String, name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.code = code
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.position = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    
        super.init()
    }
}

class MapViewDelegate: NSObject, GMSMapViewDelegate, GMUClusterManagerDelegate {
    func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        mapView.selectedMarker = marker
        return true
    }

    func clusterManager(_ clusterManager: GMUClusterManager, didTap cluster: GMUCluster) -> Bool {
        return false
    }
}

struct GoogleMapsView: UIViewRepresentable {
    @EnvironmentObject var locationManager: LocationManager
    @State private var busStops: [BusStop] = []
    private let mapViewDelegate = MapViewDelegate()
    
    private let iconGenerator = GMUDefaultClusterIconGenerator()
    private let algorithm = GMUNonHierarchicalDistanceBasedAlgorithm()
    private let renderer: GMUDefaultClusterRenderer

    init() {
        let mapView = GMSMapView()
        renderer = GMUDefaultClusterRenderer(mapView: mapView, clusterIconGenerator: iconGenerator)
    }

    func makeUIView(context: Context) -> GMSMapView {
        let userLatitude = locationManager.userLocation?.coordinate.latitude ?? 45.4215
        let userLongitude = locationManager.userLocation?.coordinate.longitude ?? -75.6972
        
        let camera = GMSCameraPosition.camera(withLatitude: userLatitude, longitude: userLongitude, zoom: 16)
        
        let mapView = GMSMapView.map(withFrame: CGRect.zero, camera: camera)
        
        mapView.isMyLocationEnabled = true
        mapView.delegate = mapViewDelegate
        mapView.mapType = GMSMapViewType.normal

        mapView.setMinZoom(16, maxZoom: 16.5)

        let clusterManager = GMUClusterManager(map: mapView, algorithm: algorithm, renderer: renderer)
        clusterManager.setDelegate(self.mapViewDelegate, mapDelegate: self.mapViewDelegate)

        fetchAllBusStops { fetchedBusStops in
            DispatchQueue.main.async {
                self.busStops = fetchedBusStops
                self.addBusStopMarkers(to: mapView, clusterManager: clusterManager)
            }
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        if let userLocation = locationManager.userLocation {
            let userLatitude = userLocation.coordinate.latitude
            let userLongitude = userLocation.coordinate.longitude
            let camera = GMSCameraPosition.camera(withLatitude: userLatitude, longitude: userLongitude, zoom: 16)
            mapView.animate(to: camera)
        }
        
        mapView.clear()
        let clusterManager = GMUClusterManager(map: mapView, algorithm: algorithm, renderer: renderer)
        clusterManager.setDelegate(self.mapViewDelegate, mapDelegate: self.mapViewDelegate)
        addBusStopMarkers(to: mapView, clusterManager: clusterManager)
    }

    private func addBusStopMarkers(to mapView: GMSMapView, clusterManager: GMUClusterManager) {
        clusterManager.clearItems()

        for busStop in busStops {
            clusterManager.add(busStop)
        }

        clusterManager.cluster()
    }
    
    func fetchAllBusStops(completion: @escaping ([BusStop]) -> Void) {
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
                let fetchedStops = response.Gtfs.map { (stop) -> BusStop in
                    BusStop(
                        id: stop.stop_id,
                        code: stop.stop_code,
                        name: stop.stop_name,
                        latitude: Double(stop.stop_lat) ?? 0.0,
                        longitude: Double(stop.stop_lon) ?? 0.0
                    )
                }
                DispatchQueue.main.async {
                    completion(fetchedStops)
                }
            } catch {
                print("Error decoding bus stops: \(error.localizedDescription)")
            }
        }.resume()
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
 */
