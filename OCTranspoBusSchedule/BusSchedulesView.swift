//
//  BusSchedulesView.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-04-05.
//
/*
import Foundation
import SwiftUI

struct BusSchedulesView: View {
    let stopNumber: String
    let routeNo: String
    @ObservedObject var viewModel: BusScheduleViewModel

    var body: some View {
        VStack {
            List(viewModel.busSchedules) { schedule in
                VStack(alignment: .leading) {
                    Text(schedule.tripDestination).font(.headline)
                    Text("Arrival: \(schedule.adjustedScheduleTime) minutes").font(.subheadline)
                }
            }
            .navigationTitle("Route \(routeNo) Schedules")
            .onAppear {
                viewModel.fetchBusSchedules(stopNumber: stopNumber, routeNo: routeNo)
            }
        }
    }
}
*/
