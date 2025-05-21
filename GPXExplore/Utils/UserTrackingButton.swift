import SwiftUI
import MapKit

#if os(iOS)
// iOS implementation using native MKUserTrackingButton
struct UserTrackingButton: UIViewRepresentable {
    var mapView: MKMapView
    
    func makeUIView(context: Context) -> MKUserTrackingButton {
        let button = MKUserTrackingButton(mapView: mapView)
        button.layer.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7).cgColor
        button.layer.cornerRadius = 5
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemGray.cgColor
        
        // Add padding
        //button.contentEdgeInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        
        return button
    }
    
    func updateUIView(_ uiView: MKUserTrackingButton, context: Context) {
        // Nothing to update - the button maintains its own state
    }
}

#elseif os(macOS)
// A user tracking button for macOS, since MapKit on macOS doesn't have a built-in one like iOS
struct UserTrackingButton: NSViewRepresentable {
    var mapView: MKMapView
    @Binding var isTracking: Bool
    
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "location", accessibilityDescription: "User Location")!,
                             target: context.coordinator,
                             action: #selector(Coordinator.toggleTracking))
        
        button.bezelStyle = .roundRect
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.wantsLayer = true
        button.toolTip = "Track User Location"
        
        return button
    }
    
    func updateNSView(_ nsView: NSButton, context: Context) {
        // Update the button's image based on tracking state
        if isTracking {
            nsView.image = NSImage(systemSymbolName: "location.fill", accessibilityDescription: "User Location Tracking")
        } else {
            nsView.image = NSImage(systemSymbolName: "location", accessibilityDescription: "User Location")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject {
        var parent: UserTrackingButton
        
        init(parent: UserTrackingButton) {
            self.parent = parent
        }
        
        @objc func toggleTracking() {
            // Toggle the tracking state
            parent.isTracking.toggle()
            
            if parent.isTracking {
                // If we're now tracking, center on user location
                if let userLocation = parent.mapView.userLocation.location {
                    let region = MKCoordinateRegion(
                        center: userLocation.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    parent.mapView.setRegion(region, animated: true)
                }
            }
        }
    }
}
#endif
