import Foundation
import SwiftUI
import MapKit

// Custom model to replace HKWorkout
struct GPXWorkout {
    let activityType: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let totalDistance: Double // in meters
    let metadata: [String: Any]
}

enum MapStyle: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"
    
    var id: String { self.rawValue }
    
    #if swift(>=5.7) && canImport(MapKit) && !targetEnvironment(macCatalyst)
    @available(iOS 16.0, *)
    var mapConfiguration: MKMapConfiguration {
        switch self {
        case .standard: return MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
        case .satellite: return MKImageryMapConfiguration()
        case .hybrid: return MKHybridMapConfiguration()
        }
    }
    #endif
    
    var mapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .satellite: return .satellite
        case .hybrid: return .hybrid
        }
    }
}

class SettingsModel: ObservableObject {
    @Published var useMetricSystem: Bool {
        didSet {
            UserDefaults.standard.set(useMetricSystem, forKey: "useMetricSystem")
        }
    }
    
    @Published var mapStyle: MapStyle {
        didSet {
            UserDefaults.standard.set(mapStyle.rawValue, forKey: "mapStyle")
        }
    }
    
    init() {
        self.useMetricSystem = UserDefaults.standard.bool(forKey: "useMetricSystem", defaultValue: true)
        
        if let savedMapStyle = UserDefaults.standard.string(forKey: "mapStyle"),
           let style = MapStyle(rawValue: savedMapStyle) {
            self.mapStyle = style
        } else {
            self.mapStyle = .standard
        }
    }
    
    func formatDistance(_ distanceInMeters: Double) -> String {
        if useMetricSystem {
            let kilometers = distanceInMeters / 1000
            return String(format: "%.2f km", kilometers)
        } else {
            let miles = distanceInMeters / 1609.34
            return String(format: "%.2f mi", miles)
        }
    }
}

extension UserDefaults {
    func bool(forKey defaultName: String, defaultValue: Bool) -> Bool {
        if object(forKey: defaultName) == nil {
            set(defaultValue, forKey: defaultName)
            return defaultValue
        }
        return bool(forKey: defaultName)
    }
}
