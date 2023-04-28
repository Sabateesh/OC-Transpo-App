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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
