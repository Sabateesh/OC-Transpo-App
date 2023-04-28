//
//  RoutePlannerView.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-04-04.
//  BETA FEATURE STILL IN WORKS
//

 import SwiftUI
 import Combine
 import CoreLocation
 import MapKit
 
struct RoutePlannerView: View {
    @StateObject private var viewModel = RoutePlannerViewModel()
    @StateObject private var locationManager = LocationManager()
    @State private var startingLocation: String = ""
    @State private var destination: String = ""
    
    var body: some View {
        VStack {
            TextField("Enter Starting Location", text: $startingLocation)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            TextField("Enter Destination", text: $destination)
                .padding()
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button(action: {
                viewModel.setUserLocation(locationManager.userLocation)
                viewModel.fetchRoutes(startingLocation: startingLocation, destination: destination)
            }) {
                Text("Find Route")
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .disabled(startingLocation.isEmpty || destination.isEmpty)
        }
        .padding()
        
    }
}
 
struct RoutePlannerView_Previews: PreviewProvider {
    static var previews: some View {
        RoutePlannerView()
    }
}

