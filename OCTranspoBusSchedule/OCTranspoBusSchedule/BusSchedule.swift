//
//  BusSchedule.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-04-03.
//

import Foundation

struct BusSchedule: Identifiable, Codable {
    let id = UUID()
    let routeNo: String
    let destination: String
    let arrivalTime: String
    let BusType: String
    let Longitude: String
    let Latitude: String
    
    enum CodingKeys: String, CodingKey {
        case routeNo = "RouteNo"
        case destination = "TripDestination"
        case arrivalTime = "AdjustedScheduleTime"
        case BusType = "BusType"
        case Longitude = "Longitude"
        case Latitude = "Latitude"
    }
}
