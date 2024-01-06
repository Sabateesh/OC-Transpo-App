//
//  ContentView.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-04-03.
//
import Combine
import Foundation
import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct ContentView: View {
    
    @StateObject private var viewModel = BusScheduleViewModel()
    @StateObject private var locationManager = LocationManager()
    private let locationManagerInstance = CLLocationManager()
    @State private var stopNumber: String = ""
    @State private var stopLabel: String = ""
    @Environment(\.colorScheme) var colorScheme
    @State private var isSnowing = true
    @State private var appleMapView: AppleMapView
    @StateObject private var rssFeedViewModel = RSSFeedViewModel()
    @State private var textFieldPadding: CGFloat = 110
    @State private var hasSearched = false // New state variable




       init() {
           let locationManager = LocationManager()
           _appleMapView = State(initialValue: AppleMapView(locationManager: locationManager))
           _locationManager = StateObject(wrappedValue: locationManager)
       }
    private func findNearestBusStop() {
        print("findNearestBusStop called")

        // Debug: Print user's current location
        if let currentUserLocation = locationManager.userLocation {
            print("User Location: \(currentUserLocation.coordinate.latitude), \(currentUserLocation.coordinate.longitude)")
        } else {
            print("User location not available")
        }

        // Debug: Print number of fetched bus stops
        print("Number of bus stops fetched: \(appleMapView.busStops.count)")

        appleMapView.findNearestBusStop { nearestStop in
            if let nearestStop = nearestStop {
                DispatchQueue.main.async {
                    self.stopNumber = nearestStop.code
                    self.stopLabel = nearestStop.name
                    print("Nearest Stop: \(nearestStop.name), Code: \(nearestStop.code)")
                }
            } else {
                print("No nearest stop found")
            }
        }
    }


    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    
    var body: some View {
        
        
        NavigationView {
            ZStack {
                VStack {
                    VStack {
                        if hasSearched {
                            AppleMapView(locationManager: locationManager)
                        }
                        
                        
                        
                        TextField("Enter Stop Number", text: $stopNumber)
                            .padding()
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                            .frame(maxWidth: .infinity)
                            .padding(.top, textFieldPadding)

                        Button(action: {
                            self.hasSearched = true
                            locationManagerInstance.requestWhenInUseAuthorization()
                            isSnowing = false
                            textFieldPadding = 0
                            viewModel.fetchBusSchedules(stopNumber: stopNumber) { result in
                                switch result {
                                case .success(let stopLabelText):
                                    stopLabel = stopLabelText
                                case .failure(_):
                                    break
                                }
                            }
                            dismissKeyboard()
                        }) {
                            Text("Fetch Bus Schedules")
                                .foregroundColor(.white)
                                .padding(.horizontal, 40)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        .disabled(stopNumber.isEmpty)
                        
                        
                    }
                    .frame(maxWidth: .infinity)
                    /*Button("Find Nearest Bus Stop") {
                                findNearestBusStop()
                            }
                     */
                    
                    
                    if !hasSearched {
                            List(viewModel.favoriteStops, id: \.self) { stop in
                                    Text("Favorite Stop: \(stopLabel) \(stop)")
                            }
                        
                            }
                    VStack {
                        if !stopLabel.isEmpty{
                            Button("Add Stop to Favorites") {
                                    viewModel.addToFavorites(stopNumber: stopNumber)
                                }
                                .padding(.horizontal, 40)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            Text("Stop: \(stopLabel)")
                                .font(.headline)
                                .padding(.bottom)
                            List {
                                ForEach(viewModel.busSchedules.keys.sorted(), id: \.self) { key in
                                    Section(header: Text(key).font(.headline)) {
                                        let topSchedules = viewModel.busSchedules[key]!.prefix(2)
                                        
                                        HStack {
                                            Text(key)
                                                .font(.largeTitle)
                                                .bold()
                                                .frame(width: 55, height: 55)
                                                .background(Color.red)
                                                .foregroundColor(.white)
                                                .cornerRadius(10)
                                                .padding(.trailing, 8)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack {
                                                    Text("\(topSchedules.first?.destination ?? "N/A")")
                                                        .font(.title3)
                                                        .bold()
                                                        .frame(width: 200, alignment: .leading)
                                                    
                                                    Spacer()
                                                    
                                                    ForEach(topSchedules.indices, id: \.self) { index in
                                                        if index > 0 {
                                                            Text("&")
                                                                .font(.footnote)
                                                        }
                                                        Text("\(topSchedules[index].arrivalTime)")
                                                            .font(.title2)
                                                            .fixedSize()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                        }
                        
                    }
                    
                    
                    if !viewModel.isBusScheduleFetched {
                        
                        Image("Ologo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 300, height: 300)
                            .offset(x: 135, y: 175)
                        
                    }
                    
                    Spacer()
                }
                .overlay(
                    Group {
                        if colorScheme == .dark && isSnowing && !iPad{
                            SnowfallView(snowflakes: 200, screenSize: UIScreen.main.bounds.size)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .allowsHitTesting(false)
                        }
                    }
                )
                .navigationBarItems(leading:
                                    Button(action: {
                                    }) {
                                        Image(uiImage: UIImage(named: "OC_Transpo_Logo") ?? UIImage(systemName: "exclamationmark.circle")!)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 50)
                                    }
                                )
                                .navigationBarItems(leading: navigationBarLeadingButton)
                                .onAppear {
                                    locationManagerInstance.requestWhenInUseAuthorization()
                                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Apply this directly to NavigationView

    }
    
    
    var navigationBarLeadingButton: some View {
            Button(action: {
                withAnimation {
                    viewModel.isPresentingHomeView.toggle()
                }
            }) {
            }
        }
    
    var iPad: Bool {
            UIDevice.current.userInterfaceIdiom == .pad
        }
    
    var smallerScreen: Bool {
            UIScreen.main.bounds.width < 375
        }
}



struct Snowflake {
    var id = UUID()
    var x: CGFloat // X position
    var y: CGFloat // Y position
    var speed: CGFloat // Falling speed
    var size: CGFloat // Size of the snowflake
}



struct SnowfallView: View {
    let snowflakes: Int
    let screenSize: CGSize
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()


    @State private var flakes: [Snowflake] = []

    var body: some View {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    for flake in flakes {
                        let frame = CGRect(x: flake.x, y: flake.y, width: flake.size, height: flake.size)
                        context.fill(Path(ellipseIn: frame), with: .color(.white))
                    }
                }
            }
        .onAppear {
            for _ in 0..<snowflakes {
                let flake = Snowflake(
                    x: CGFloat.random(in: 0...6000),
                    y: CGFloat.random(in: -100...screenSize.height),
                    speed: CGFloat.random(in: 1...5),
                    size: CGFloat.random(in: 2...8)
                )
                flakes.append(flake)
            }
        }
        .onReceive(timer) { _ in
                    updateSnowflakes(size: screenSize)
        }
    }

    func updateSnowflakes(size: CGSize) {
            for i in flakes.indices {
                flakes[i].y += flakes[i].speed
                if flakes[i].y > size.height {
                    flakes[i] = Snowflake(
                        x: CGFloat.random(in: 0...600),
                        y: -10,
                        speed: CGFloat.random(in: 1...5),
                        size: CGFloat.random(in: 2...8)
                    )
                }
            }
        }
    }
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(LocationManager())
    }
    

}
/*
 import Combine
 import Foundation
 import SwiftUI
 import MapKit
 import CoreLocation
 import UIKit

 struct ContentView: View {
     @StateObject private var viewModel = BusScheduleViewModel()
     @StateObject private var locationManager = LocationManager()
     private let locationManagerInstance = CLLocationManager()
     @State private var stopNumber: String = ""
     @State private var stopLabel: String = ""
     @Environment(\.colorScheme) var colorScheme
     


     var body: some View {
         NavigationView {
             ZStack {
                 VStack {
                     VStack {
                         TextField("Enter Stop Number", text: $stopNumber)
                             .padding()
                             .textFieldStyle(RoundedBorderTextFieldStyle())
                             .keyboardType(.numberPad)

                         Button(action: {
                             locationManagerInstance.requestWhenInUseAuthorization()
                             viewModel.fetchBusSchedules(stopNumber: stopNumber) { result in
                                 switch result {
                                 case .success(let stopLabelText):
                                     stopLabel = stopLabelText
                                 case .failure(_):
                                     break
                                 }
                             }
                         }) {
                             Text("Fetch Bus Schedules")
                                 .foregroundColor(.white)
                                 .padding(.horizontal, 40)
                                 .padding(.vertical, 10)
                                 .background(Color.blue)
                                 .cornerRadius(10)
                         }
                         .disabled(stopNumber.isEmpty)
                     }

                     VStack {
                         Text("Stop: \(stopLabel)")
                             .font(.headline)
                             .padding(.bottom)
                         List {
                             ForEach(viewModel.busSchedules.keys.sorted(), id: \.self) { key in
                                 Section(header: Text(key).font(.headline)) {
                                     let topSchedules = viewModel.busSchedules[key]!.prefix(2)

                                     HStack {
                                         Text(key)
                                             .font(.largeTitle)
                                             .bold()
                                             .frame(width: 50, height: 50)
                                             .background(Color.red)
                                             .foregroundColor(.white)
                                             .cornerRadius(10)
                                             .padding(.trailing, 8)

                                         VStack(alignment: .leading, spacing: 2) {
                                             HStack {
                                                 Text("\(topSchedules.first?.destination ?? "N/A")")
                                                     .font(.title3)
                                                     .bold()
                                                     .frame(width: 200, alignment: .leading)

                                                 Spacer()

                                                 ForEach(topSchedules.indices, id: \.self) { index in
                                                     if index > 0 {
                                                         Text(" & ")
                                                             .font(.footnote)
                                                     }
                                                     Text("\(topSchedules[index].arrivalTime)")
                                                         .font(.footnote)
                                                         .fixedSize()
                                                 }
                                             }
                                         }
                                     }
                                 }
                             }
                         }
                         
                     }
                     if !viewModel.isBusScheduleFetched {
                         Image("Ologo")
                             .resizable()
                             .scaledToFit()
                             .frame(width: 500, height: 500)
                             .offset(x: 125, y: 175)
                     }

                     Spacer()
                 }
                 .overlay(
                     Group {
                         if colorScheme == .dark {
                             SnowfallView(snowflakes: 200, screenSize: UIScreen.main.bounds.size)
                                 .frame(maxWidth: .infinity, maxHeight: .infinity)
                                 .allowsHitTesting(false)
                         }
                     }
                 )
                 .navigationBarItems(leading:
                     Button(action: {
                         withAnimation {
                             viewModel.isPresentingHomeView.toggle()
                         }
                     }) {
                         Image(uiImage: UIImage(named: "OC_Transpo_Logo") ?? UIImage(systemName: "exclamationmark.circle")!)
                             .resizable()
                             .scaledToFit()
                             .frame(height: 50)
                     }
                 )
                 .padding(.top)

                 .onAppear {
                     locationManagerInstance.requestWhenInUseAuthorization()
                 }
             }
         }
     }
 }


 struct Snowflake {
     var id = UUID()
     var x: CGFloat // X position
     var y: CGFloat // Y position
     var speed: CGFloat // Falling speed
     var size: CGFloat // Size of the snowflake
 }



 struct SnowfallView: View {
     let snowflakes: Int
     let screenSize: CGSize
     let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()


     @State private var flakes: [Snowflake] = []

     var body: some View {
             TimelineView(.animation) { timeline in
                 Canvas { context, size in
                     for flake in flakes {
                         let frame = CGRect(x: flake.x, y: flake.y, width: flake.size, height: flake.size)
                         context.fill(Path(ellipseIn: frame), with: .color(.white))
                     }
                 }
             }
         .onAppear {
             for _ in 0..<snowflakes {
                 let flake = Snowflake(
                     x: CGFloat.random(in: 0...6000),
                     y: CGFloat.random(in: -100...screenSize.height),
                     speed: CGFloat.random(in: 1...5),
                     size: CGFloat.random(in: 2...8)
                 )
                 flakes.append(flake)
             }
         }
         .onReceive(timer) { _ in
                     updateSnowflakes(size: screenSize)
         }
     }

     func updateSnowflakes(size: CGSize) {
             for i in flakes.indices {
                 flakes[i].y += flakes[i].speed
                 if flakes[i].y > size.height {
                     flakes[i] = Snowflake(
                         x: CGFloat.random(in: 0...600),
                         y: -10,
                         speed: CGFloat.random(in: 1...5),
                         size: CGFloat.random(in: 2...8)
                     )
                 }
             }
         }
     }
 struct ContentView_Previews: PreviewProvider {
     static var previews: some View {
         ContentView()
     }
 }

 
 
 
 
 
 
 import Combine
 import Foundation
 import SwiftUI
 import MapKit
 import CoreLocation
 import UIKit

 struct ContentView: View {
     @StateObject private var viewModel = BusScheduleViewModel()
     @StateObject private var locationManager = LocationManager()
     private let locationManagerInstance = CLLocationManager()
     @State private var stopNumber: String = ""
     @State private var stopLabel: String = ""
     @Environment(\.colorScheme) var colorScheme
     @State private var isSnowing = true
     @State private var appleMapView: AppleMapView

        init() {
            let locationManager = LocationManager()
            _appleMapView = State(initialValue: AppleMapView(locationManager: locationManager))
            _locationManager = StateObject(wrappedValue: locationManager)
        }

     private func findNearestBusStop() {
         appleMapView.findNearestBusStop { nearestStop in
             if let nearestStop = nearestStop {
                 DispatchQueue.main.async {
                     self.stopNumber = nearestStop.code
                     self.stopLabel = nearestStop.name
                 }
             }
         }
     }
     
     var body: some View {
         NavigationView {
             ZStack {
                 AppleMapView(locationManager: locationManager)
                                     .hidden()
                 
                 VStack {
                     VStack {
                         TextField("Enter Stop Number", text: $stopNumber)
                             .padding()
                             .textFieldStyle(RoundedBorderTextFieldStyle())
                             .keyboardType(.numberPad)
                             .frame(maxWidth: .infinity)

                         Button(action: {
                             locationManagerInstance.requestWhenInUseAuthorization()
                             isSnowing = false
                             viewModel.fetchBusSchedules(stopNumber: stopNumber) { result in
                                 switch result {
                                 case .success(let stopLabelText):
                                     stopLabel = stopLabelText
                                 case .failure(_):
                                     break
                                 }
                             }
                         }) {
                             Text("Fetch Bus Schedules")
                                 .foregroundColor(.white)
                                 .padding(.horizontal, 40)
                                 .padding(.vertical, 10)
                                 .background(Color.blue)
                                 .cornerRadius(10)
                         }
                         .disabled(stopNumber.isEmpty)
                     }
                     .frame(maxWidth: .infinity)
                     Button("Find Nearest Bus Stop") {
                                 findNearestBusStop()
                             }
                     VStack {
                         Text("Stop: \(stopLabel)")
                             .font(.headline)
                             .padding(.bottom)
                         List {
                             ForEach(viewModel.busSchedules.keys.sorted(), id: \.self) { key in
                                 Section(header: Text(key).font(.headline)) {
                                     let topSchedules = viewModel.busSchedules[key]!.prefix(2)

                                     HStack {
                                         Text(key)
                                             .font(.largeTitle)
                                             .bold()
                                             .frame(width: 55, height: 55)
                                             .background(Color.red)
                                             .foregroundColor(.white)
                                             .cornerRadius(10)
                                             .padding(.trailing, 8)

                                         VStack(alignment: .leading, spacing: 2) {
                                             HStack {
                                                 Text("\(topSchedules.first?.destination ?? "N/A")")
                                                     .font(.title3)
                                                     .bold()
                                                     .frame(width: 200, alignment: .leading)

                                                 Spacer()

                                                 ForEach(topSchedules.indices, id: \.self) { index in
                                                     if index > 0 {
                                                         Text(" & ")
                                                             .font(.footnote)
                                                     }
                                                     Text("\(topSchedules[index].arrivalTime)")
                                                         .font(.footnote)
                                                         .fixedSize()
                                                 }
                                             }
                                         }
                                     }
                                 }
                             }
                         }
                         
                     }
                     if !viewModel.isBusScheduleFetched {
                         Image("Ologo")
                             .resizable()
                             .scaledToFit()
                             .frame(width: 500, height: 500)
                             .offset(x: 125, y: 175)
                     }

                     Spacer()
                 }
                 .overlay(
                     Group {
                         if colorScheme == .dark && isSnowing {
                             SnowfallView(snowflakes: 200, screenSize: UIScreen.main.bounds.size)
                                 .frame(maxWidth: .infinity, maxHeight: .infinity)
                                 .allowsHitTesting(false)
                         }
                     }
                 )
                 .navigationBarItems(leading:
                     Button(action: {
                         withAnimation {
                             viewModel.isPresentingHomeView.toggle()
                         }
                     }) {
                         Image(uiImage: UIImage(named: "OC_Transpo_Logo") ?? UIImage(systemName: "exclamationmark.circle")!)
                             .resizable()
                             .scaledToFit()
                             .frame(height: 50)
                     }
                 )
                 .padding(.top)

                 .onAppear {
                     locationManagerInstance.requestWhenInUseAuthorization()
                 }
             }
         }
     }
 }


 struct Snowflake {
     var id = UUID()
     var x: CGFloat // X position
     var y: CGFloat // Y position
     var speed: CGFloat // Falling speed
     var size: CGFloat // Size of the snowflake
 }



 struct SnowfallView: View {
     let snowflakes: Int
     let screenSize: CGSize
     let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()


     @State private var flakes: [Snowflake] = []

     var body: some View {
             TimelineView(.animation) { timeline in
                 Canvas { context, size in
                     for flake in flakes {
                         let frame = CGRect(x: flake.x, y: flake.y, width: flake.size, height: flake.size)
                         context.fill(Path(ellipseIn: frame), with: .color(.white))
                     }
                 }
             }
         .onAppear {
             for _ in 0..<snowflakes {
                 let flake = Snowflake(
                     x: CGFloat.random(in: 0...6000),
                     y: CGFloat.random(in: -100...screenSize.height),
                     speed: CGFloat.random(in: 1...5),
                     size: CGFloat.random(in: 2...8)
                 )
                 flakes.append(flake)
             }
         }
         .onReceive(timer) { _ in
                     updateSnowflakes(size: screenSize)
         }
     }

     func updateSnowflakes(size: CGSize) {
             for i in flakes.indices {
                 flakes[i].y += flakes[i].speed
                 if flakes[i].y > size.height {
                     flakes[i] = Snowflake(
                         x: CGFloat.random(in: 0...600),
                         y: -10,
                         speed: CGFloat.random(in: 1...5),
                         size: CGFloat.random(in: 2...8)
                     )
                 }
             }
         }
     }
 struct ContentView_Previews: PreviewProvider {
     static var previews: some View {
         ContentView().environmentObject(LocationManager())
     }
 }
 */
