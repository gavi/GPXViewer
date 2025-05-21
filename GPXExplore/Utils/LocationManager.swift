import Foundation
import CoreLocation
import MapKit
import SwiftUI

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    
    private var locationManager = CLLocationManager()
    
    @Published var userLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var showLocationPermissionAlert = false
    
    override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Listen for notifications to show user location
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowUserLocation),
            name: Notification.Name("ShowUserLocation"),
            object: nil
        )
    }
    
    @objc func handleShowUserLocation() {
        requestLocationIfNeeded()
        
        if let location = userLocation {
            // Notify map to center on user location
            NotificationCenter.default.post(
                name: Notification.Name("CenterOnUserLocation"),
                object: nil,
                userInfo: ["location": location]
            )
        } else {
            // Try to get a single update
            locationManager.requestLocation()
        }
    }
    
    func requestLocationIfNeeded() {
        let status = locationManager.authorizationStatus
        
        switch status {
        case .notDetermined:
            #if os(iOS)
            locationManager.requestWhenInUseAuthorization()
            #elseif os(macOS)
            locationManager.requestAlwaysAuthorization()
            #endif
        case .restricted, .denied:
            // Show alert that permissions are needed
            showLocationPermissionAlert = true
        #if os(iOS)
        case .authorizedWhenInUse, .authorizedAlways:
            // Already authorized, nothing to do
            break
        #elseif os(macOS)
        case .authorized, .authorizedAlways:
            // Already authorized, nothing to do
            break
        #endif
        @unknown default:
            break
        }
    }
    
    func startUpdatingLocation() {
        #if os(iOS)
        if locationManager.authorizationStatus == .authorizedWhenInUse || 
           locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
        #elseif os(macOS)
        if locationManager.authorizationStatus == .authorized || 
           locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
        #endif
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        #if os(iOS)
        if manager.authorizationStatus == .authorizedWhenInUse || 
           manager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
        #elseif os(macOS)
        if manager.authorizationStatus == .authorized || 
           manager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
        #endif
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location
        
        // If this was called in response to a "show user location" request, center the map
        if let _ = userLocation {
            NotificationCenter.default.post(
                name: Notification.Name("CenterOnUserLocation"),
                object: nil,
                userInfo: ["location": location]
            )
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
}