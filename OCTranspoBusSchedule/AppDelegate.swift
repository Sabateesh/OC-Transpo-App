//
//  AppDelegate.swift
//  OCTranspoBusSchedule
//
//  Created by Sabateesh Sivakumar on 2023-04-09.
//

import GoogleMaps
import GooglePlaces
import SDWebImage

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        GMSServices.provideAPIKey("NOTPUBLIC")
        GMSPlacesClient.provideAPIKey("NOTPUBLIC")
        
        return true
    }
}
