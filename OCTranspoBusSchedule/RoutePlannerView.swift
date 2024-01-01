//
//  RoutePlannerView.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-04-04.
//  BETA FEATURE STILL IN WORKS
//
import SwiftUI
import MapKit

struct RoutePlannerView: View {
    @EnvironmentObject var locationManager: LocationManager
    @State private var destination: String = ""
    @State private var directions: [String] = []
    @State private var showDirections = false
    @State private var route: MKRoute?
    @State private var searchCompleter = MKLocalSearchCompleter()
    @State private var completerResults: [MKLocalSearchCompletion] = []
    @State private var searchCompleterDelegate: SearchCompleterDelegate?
    @State private var transitETA: String = ""



    
    var body: some View {
        VStack {
            TextField("Enter Destination", text: $destination, onEditingChanged: { _ in
                updateSearchResults()
            })
            .padding()
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .onChange(of: destination, perform: { value in
                searchCompleter.queryFragment = value
                if value.isEmpty || value != destination {
                    // Reset the showDirections when the query changes
                    showDirections = false
                }
            })
            
            // Only display auto-complete results when there's an active search
            if !destination.isEmpty && !showDirections {
                            List(completerResults, id: \.self) { result in
                                Text(result.title)
                                    .onTapGesture {
                                        self.destination = result.title
                                        self.completerResults = []
                                    }
                            }
                        }

            Button("Get Directions") {
                calculateRoute()
                self.completerResults = []
            }
            .disabled(destination.isEmpty)
            .padding()

            MapView(route: $route)
                .frame(height: 300)

            if showDirections {
                // Show transit ETA
                if !transitETA.isEmpty {
                    Text("Estimated Transit Time: \(transitETA)")
                        .padding()
                }

                // Show directions list
                List(directions, id: \.self) { direction in
                    Text(direction).padding()
                }
            }
        }
        .onAppear {
            self.searchCompleterDelegate = SearchCompleterDelegate(completerResults: $completerResults)
            searchCompleter.delegate = self.searchCompleterDelegate
        }
    }

    private func calculateRoute() {
        guard let userLocation = locationManager.userLocation else { return }
        let userPlacemark = MKPlacemark(coordinate: userLocation.coordinate)

        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(destination) { placemarks, error in
            guard let destinationPlacemark = placemarks?.first else { return }

            let destinationCoordinate = destinationPlacemark.location?.coordinate
            guard let coordinate = destinationCoordinate else { return }
            let mkDestinationPlacemark = MKPlacemark(coordinate: coordinate)

            // Request for driving directions
            let requestForDriving = MKDirections.Request()
            requestForDriving.source = MKMapItem(placemark: userPlacemark)
            requestForDriving.destination = MKMapItem(placemark: mkDestinationPlacemark)
            requestForDriving.transportType = .automobile

            let drivingDirections = MKDirections(request: requestForDriving)
            drivingDirections.calculate { response, error in
                guard let route = response?.routes.first else { return }

                self.route = route
                self.directions = route.steps.map { $0.instructions }.filter { !$0.isEmpty }
                self.showDirections = true
            }

            // Request for transit ETA
            let requestForTransit = MKDirections.Request()
            requestForTransit.source = MKMapItem(placemark: userPlacemark)
            requestForTransit.destination = MKMapItem(placemark: mkDestinationPlacemark)
            requestForTransit.transportType = .transit

            let transitDirections = MKDirections(request: requestForTransit)
            transitDirections.calculateETA { response, error in
                guard let etaResponse = response else { return }

                let eta = etaResponse.expectedTravelTime
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute]
                formatter.unitsStyle = .short
                DispatchQueue.main.async {
                    self.transitETA = formatter.string(from: eta) ?? "N/A"
                }
            }
        }
    }
    
    private func updateSearchResults() {
        if destination.isEmpty {
            completerResults = []
        } else {
            searchCompleter.queryFragment = destination
        }
    }
}

struct MapView: UIViewRepresentable {
    typealias UIViewType = MKMapView
    @Binding var route: MKRoute?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator // Set the delegate
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.removeOverlays(uiView.overlays) // Clear existing overlays

        if let route = route {
            uiView.addOverlay(route.polyline)
            uiView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView

        init(_ parent: MapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}


struct RoutePlannerView_Previews: PreviewProvider {
    static var previews: some View {
        RoutePlannerView().environmentObject(LocationManager())
    }
}


class SearchCompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
    @Binding var completerResults: [MKLocalSearchCompletion]

    init(completerResults: Binding<[MKLocalSearchCompletion]>) {
        self._completerResults = completerResults
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        completerResults = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Completer error: \(error.localizedDescription)")
    }
}

 

/*
 import SwiftUI
 import MapKit

 struct RoutePlannerView: View {
     @EnvironmentObject var locationManager: LocationManager
     @State private var destination: String = ""
     @State private var directions: [String] = []
     @State private var showDirections = false
     @State private var route: MKRoute?
     @State private var searchCompleter = MKLocalSearchCompleter()
     @State private var completerResults: [MKLocalSearchCompletion] = []
     @State private var searchCompleterDelegate: SearchCompleterDelegate?
     @State private var transitETA: String = ""



     var body: some View {
         VStack {
             TextField("Enter Destination", text: $destination, onEditingChanged: { _ in
                 updateSearchResults()
             })
             .padding()
             .textFieldStyle(RoundedBorderTextFieldStyle())
             .onChange(of: destination, perform: { value in
                 searchCompleter.queryFragment = value
                 if value.isEmpty || value != destination {
                     // Reset the showDirections when the query changes
                     showDirections = false
                 }
             })
             
             // Only display auto-complete results when there's an active search
             if !destination.isEmpty && !showDirections {
                             List(completerResults, id: \.self) { result in
                                 Text(result.title)
                                     .onTapGesture {
                                         self.destination = result.title
                                         self.completerResults = []
                                     }
                             }
                         }

             Button("Get Directions") {
                 calculateRoute()
                 self.completerResults = []
             }
             .disabled(destination.isEmpty)
             .padding()

             MapView(route: $route)
                 .frame(height: 300)

             if showDirections {
                 // Show transit ETA
                 if !transitETA.isEmpty {
                     Text("Estimated Transit Time: \(transitETA)")
                         .padding()
                 }

                 // Show directions list
                 List(directions, id: \.self) { direction in
                     Text(direction).padding()
                 }
             }
         }
         .onAppear {
             self.searchCompleterDelegate = SearchCompleterDelegate(completerResults: $completerResults)
             searchCompleter.delegate = self.searchCompleterDelegate
         }
     }

     private func calculateRoute() {
         guard let userLocation = locationManager.userLocation else { return }
         let userPlacemark = MKPlacemark(coordinate: userLocation.coordinate)

         let geocoder = CLGeocoder()
         geocoder.geocodeAddressString(destination) { placemarks, error in
             guard let destinationPlacemark = placemarks?.first else { return }

             let destinationCoordinate = destinationPlacemark.location?.coordinate
             guard let coordinate = destinationCoordinate else { return }
             let mkDestinationPlacemark = MKPlacemark(coordinate: coordinate)

             let request = MKDirections.Request()
             request.source = MKMapItem(placemark: userPlacemark)
             request.destination = MKMapItem(placemark: mkDestinationPlacemark)
             request.transportType = .automobile // or .transit based on availability

             let directions = MKDirections(request: request)
             directions.calculate { response, error in
                 guard let route = response?.routes.first else { return }
                 
                 self.route = route
                 self.directions = route.steps.map { $0.instructions }.filter { !$0.isEmpty }
                 self.showDirections = true

                 // Calculating ETA
                 let eta = route.expectedTravelTime
                 let formatter = DateComponentsFormatter()
                 formatter.allowedUnits = [.hour, .minute]
                 formatter.unitsStyle = .short
                 DispatchQueue.main.async {
                     self.transitETA = formatter.string(from: eta) ?? "N/A"
                 }
             }
         }
     }
     
     private func updateSearchResults() {
         if destination.isEmpty {
             completerResults = []
         } else {
             searchCompleter.queryFragment = destination
         }
     }
 }

 struct MapView: UIViewRepresentable {
     typealias UIViewType = MKMapView
     @Binding var route: MKRoute?

     func makeUIView(context: Context) -> MKMapView {
         let mapView = MKMapView(frame: .zero)
         mapView.delegate = context.coordinator // Set the delegate
         return mapView
     }

     func updateUIView(_ uiView: MKMapView, context: Context) {
         uiView.removeOverlays(uiView.overlays) // Clear existing overlays

         if let route = route {
             uiView.addOverlay(route.polyline)
             uiView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), animated: true)
         }
     }

     func makeCoordinator() -> Coordinator {
         Coordinator(self)
     }

     class Coordinator: NSObject, MKMapViewDelegate {
         var parent: MapView

         init(_ parent: MapView) {
             self.parent = parent
         }

         func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
             if let polyline = overlay as? MKPolyline {
                 let renderer = MKPolylineRenderer(polyline: polyline)
                 renderer.strokeColor = .blue
                 renderer.lineWidth = 4
                 return renderer
             }
             return MKOverlayRenderer(overlay: overlay)
         }
     }
 }


 struct RoutePlannerView_Previews: PreviewProvider {
     static var previews: some View {
         RoutePlannerView().environmentObject(LocationManager())
     }
 }


 class SearchCompleterDelegate: NSObject, MKLocalSearchCompleterDelegate {
     @Binding var completerResults: [MKLocalSearchCompletion]

     init(completerResults: Binding<[MKLocalSearchCompletion]>) {
         self._completerResults = completerResults
     }

     func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
         completerResults = completer.results
     }

     func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
         print("Completer error: \(error.localizedDescription)")
     }
 }

 */
