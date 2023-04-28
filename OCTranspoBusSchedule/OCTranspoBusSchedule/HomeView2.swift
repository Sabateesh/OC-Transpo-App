//
//  HomeView2.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-04-07.
//

import Foundation
import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack {
            Text("Welcome to the Bus Schedule and Route Planner App")
                .font(.headline)
                .padding()
            Spacer()
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}
