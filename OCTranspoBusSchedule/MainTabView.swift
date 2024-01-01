//
//  MainTabView.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-04-07.
//
//
import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var viewModel: BusScheduleViewModel
    @StateObject private var locationManager = LocationManager()
    
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("Bus Schedule", systemImage: "bus")
                }
                .environmentObject(locationManager)
            
            RoutePlannerView()
                .tabItem {
                    Label("Route Planner", systemImage: "figure.walk")
                }

            AppleMapView(locationManager: locationManager)
                .tabItem{
                    Label("Maps", systemImage: "map.circle.fill")
                }
                .environmentObject(locationManager)
            }
        .sheet(isPresented: $viewModel.isPresentingHomeView) {
            HomeView()
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView().environmentObject(BusScheduleViewModel())
    }
}
