//
//  OCTranspoBusScheduleApp.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-04-03.

import SwiftUI

@main
struct OCTranspoBusScheduleApp: App {
    @StateObject private var viewModel = BusScheduleViewModel()
       @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

       var body: some Scene {
           WindowGroup {
               MainTabView()
                   .environmentObject(viewModel)
           }
       }
}
