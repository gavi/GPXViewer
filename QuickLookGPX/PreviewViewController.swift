//
//  PreviewViewController.swift
//  QuickLookGPX
//
//  Created by Gavi Narra on 5/8/25.
//

import Cocoa
import Quartz
import MapKit
import CoreLocation

class PreviewViewController: NSViewController, QLPreviewingController {
    // Map view for displaying the GPX track
    private let mapView = MKMapView()
    private let statsLabel = NSTextField(wrappingLabelWithString: "")
    
    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }
    
    override func loadView() {
        super.loadView()
        
        // Setup view with a split layout - map on top, stats below
        let containerView = NSView(frame: view.bounds)
        containerView.autoresizingMask = [.width, .height]
        view = containerView
        
        
        // Configure map view (taking up top 2/3 of the space)
        let mapHeight = view.bounds.height * 0.7
        mapView.frame = CGRect(x: 0, y: view.bounds.height - mapHeight, width: view.bounds.width, height: mapHeight)
        mapView.autoresizingMask = [.width, .height]
        mapView.delegate = self
        mapView.mapType = .standard
        
        // Set some visual properties to make the empty map more visually appealing
        mapView.wantsLayer = true
        mapView.layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1.0).cgColor
        
        // Add a background label indicating map limitations
        let backgroundLabel = NSTextField(labelWithString: "Basemap may not appear in Quick Look")
        backgroundLabel.textColor = NSColor.tertiaryLabelColor
        backgroundLabel.alignment = .center
        backgroundLabel.font = NSFont.systemFont(ofSize: 14)
        backgroundLabel.frame = mapView.bounds
        backgroundLabel.autoresizingMask = [.width, .height]
        mapView.addSubview(backgroundLabel)
        view.addSubview(mapView)
        
        // Configure stats label (bottom 1/3)
        statsLabel.frame = CGRect(x: 10, y: 10, width: view.bounds.width - 20, height: view.bounds.height - mapHeight - 20)
        statsLabel.autoresizingMask = [.width, .height]
        statsLabel.font = NSFont.systemFont(ofSize: 12)
        statsLabel.alignment = .left
        view.addSubview(statsLabel)
    }
    
    func preparePreviewOfFile(at url: URL) async throws {
        // Parse the GPX file using existing GPXParser
        let gpxFile = GPXParser.parseGPXFile(at: url)
        
        // Ensure we have tracks to display
        guard !gpxFile.tracks.isEmpty else {
            statsLabel.stringValue = "No tracks found in GPX file"
            return
        }
        
        // Collect all track segments from the file
        let trackSegments = gpxFile.allSegments
        var allLocations: [CLLocation] = []
        
        // Process each segment to add to map
        for segment in trackSegments {
            let locations = segment.locations
            guard !locations.isEmpty else { continue }
            
            allLocations.append(contentsOf: locations)
            
            // Create simple polyline for the segment - make it thicker to be more visible
            let coordinates = locations.map { $0.coordinate }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)
        }
        
        // Add basic waypoints if any
        if !gpxFile.waypoints.isEmpty {
            let waypoints = gpxFile.waypoints.map { waypoint -> MKPointAnnotation in
                let annotation = MKPointAnnotation()
                annotation.coordinate = waypoint.coordinate
                annotation.title = waypoint.name
                return annotation
            }
            mapView.addAnnotations(waypoints)
        }
        
        // Set map region to show all points
        if !allLocations.isEmpty {
            setMapRegion(for: mapView, from: allLocations)
        }
        
        // Calculate statistics for display
        var statsText = "GPX File: \(gpxFile.filename)\n\n"
        
        // Basic counts
        statsText += "Contents:\n"
        statsText += "• \(gpxFile.tracks.count) track(s)\n"
        statsText += "• \(gpxFile.allSegments.count) segment(s)\n"
        statsText += "• \(gpxFile.waypoints.count) waypoint(s)\n"
        
        // Calculate totals
        var totalDistance = 0.0
        var totalTime: TimeInterval = 0
        var totalAscent = 0.0
        var totalDescent = 0.0
        var pointCount = 0
        
        for track in gpxFile.tracks {
            let workout = track.workout
            totalDistance += workout.totalDistance
            totalTime += workout.duration
            pointCount += track.allLocations.count
            
            // Sum elevation changes
            for segment in track.segments {
                if segment.locations.count > 1 {
                    for i in 1..<segment.locations.count {
                        let elevDiff = segment.locations[i].altitude - segment.locations[i-1].altitude
                        if elevDiff > 1.0 {
                            totalAscent += elevDiff
                        } else if elevDiff < -1.0 {
                            totalDescent += abs(elevDiff)
                        }
                    }
                }
            }
        }
        
        // Format statistics
        statsText += "\nStats:\n"
        
        // Distance
        let distanceFormatter = MeasurementFormatter()
        distanceFormatter.unitOptions = .providedUnit
        distanceFormatter.numberFormatter.maximumFractionDigits = 1
        let distanceMeasurement = Measurement(value: totalDistance, unit: UnitLength.meters)
        statsText += "• Distance: \(distanceFormatter.string(from: distanceMeasurement))\n"
        
        // Duration
        let durationFormatter = DateComponentsFormatter()
        durationFormatter.allowedUnits = [.hour, .minute, .second]
        durationFormatter.unitsStyle = .abbreviated
        if let formattedDuration = durationFormatter.string(from: totalTime) {
            statsText += "• Duration: \(formattedDuration)\n"
        }
        
        // Elevation
        let elevFormatter = MeasurementFormatter()
        elevFormatter.unitOptions = .providedUnit
        elevFormatter.numberFormatter.maximumFractionDigits = 0
        let ascentMeasurement = Measurement(value: totalAscent, unit: UnitLength.meters)
        let descentMeasurement = Measurement(value: totalDescent, unit: UnitLength.meters)
        statsText += "• Elevation Gain: \(elevFormatter.string(from: ascentMeasurement))\n"
        statsText += "• Elevation Loss: \(elevFormatter.string(from: descentMeasurement))\n"
        statsText += "• Total Points: \(pointCount)"
        
        // Update stats label
        statsLabel.stringValue = statsText
    }
    
    // Helper method to set the map region
    private func setMapRegion(for mapView: MKMapView, from locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        
        // Find min/max coordinates
        var minLat = locations[0].coordinate.latitude
        var maxLat = minLat
        var minLon = locations[0].coordinate.longitude
        var maxLon = minLon
        
        for location in locations {
            minLat = min(minLat, location.coordinate.latitude)
            maxLat = max(maxLat, location.coordinate.latitude)
            minLon = min(minLon, location.coordinate.longitude)
            maxLon = max(maxLon, location.coordinate.longitude)
        }
        
        // Create region with padding
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5,
            longitudeDelta: (maxLon - minLon) * 1.5
        )
        
        // Ensure minimum zoom level
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(span.latitudeDelta, 0.01),
                longitudeDelta: max(span.longitudeDelta, 0.01)
            )
        )
        
        mapView.setRegion(region, animated: false)
    }
}

// Implement MKMapViewDelegate to render the polylines
extension PreviewViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            
            // Use a bright, highly visible color for tracks that will show up on any background
            renderer.strokeColor = NSColor.systemRed
            
            // Make lines thicker to be more visible even without map tiles
            renderer.lineWidth = 5.0
            
            // Add a stroke effect to make it stand out more
            renderer.lineCap = .round
            renderer.lineJoin = .round
            
            // Optional: you could add a shadow effect, though this might not render in the sandbox
            // renderer.setShadow(NSShadow())
            
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !annotation.isKind(of: MKUserLocation.self) else { return nil }
        
        let identifier = "GPXPointAnnotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = annotation
        }
        
        if let markerView = annotationView as? MKMarkerAnnotationView {
                // Style markers differently based on type
            if annotation.title == "Start" {
                markerView.markerTintColor = .systemGreen
                markerView.glyphText = "S"
            } else if annotation.title == "End" {
                markerView.markerTintColor = .systemRed
                markerView.glyphText = "E"
            } else {
                // Waypoint styling
                markerView.markerTintColor = .systemBlue
                markerView.glyphText = "W"
            }
        }
        
        return annotationView
    }
}