import SwiftUI
import MapKit
import CoreLocation

#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
#endif

// Enhanced polyline object to store elevation data and gradients
class ElevationPolyline: MKPolyline {
    // Basic elevation data
    var elevations: [CLLocationDistance] = []
    var minElevation: CLLocationDistance = 0
    var maxElevation: CLLocationDistance = 0
    
    // Enhanced data for Garmin-like visualization
    var grades: [Double] = []        // Store the grade (steepness) between each point
    var maxGrade: Double = 0         // Maximum grade (uphill)
    var minGrade: Double = 0         // Minimum grade (downhill)
    var totalAscent: Double = 0      // Total elevation gain
    var totalDescent: Double = 0     // Total elevation loss
    
    // Calculate enhanced statistics after setting elevations
    func calculateGradeData(from locations: [CLLocation]) {
        guard locations.count > 1 && elevations.count == locations.count else { 
            print("ERROR: Cannot calculate grade data - invalid locations or elevations")
            return 
        }
        
        // First, smooth the elevation data to reduce GPS noise
        smoothElevationData()
        
        var currentAscent: Double = 0
        var currentDescent: Double = 0
        grades = Array(repeating: 0, count: elevations.count)
        
        // Use a sliding window for calculating grades to reduce noise
        let windowSize = min(5, locations.count / 10 + 1) // Adaptive window size
        print("Using window size \(windowSize) for \(locations.count) locations")
        
        for i in 0..<(locations.count - 1) {
            // Calculate start and end indices for the window
            let startIdx = max(0, i - windowSize)
            let endIdx = min(locations.count - 1, i + windowSize)
            
            if endIdx > startIdx {
                // Use points at the edges of the window for more stable grade calculation
                let elevation1 = elevations[startIdx]
                let elevation2 = elevations[endIdx]
                let location1 = locations[startIdx]
                let location2 = locations[endIdx]
                
                // Calculate horizontal distance over the window
                let horizontalDistance = location1.distance(from: location2)
                
                // Calculate grade (avoid division by zero)
                var grade = 0.0
                if horizontalDistance > 5.0 { // Require more substantial distance for good grade calculation
                    grade = (elevation2 - elevation1) / horizontalDistance
                    
                    // Apply realistic limits to grades (real-world trails rarely exceed 35%)
                    let originalGrade = grade
                    grade = min(max(grade, -0.45), 0.45)
                    
                    // Debug every 20th point to avoid console flood
                    if i % 20 == 0 {
                        //print("Point \(i): window \(startIdx)-\(endIdx), elev diff: \(elevation2-elevation1)m, " +
                              //"horiz dist: \(horizontalDistance)m, grade: \(originalGrade) → \(grade)")
                    }
                } else if i % 20 == 0 {
                    //print("Point \(i): window \(startIdx)-\(endIdx), horizontal distance too small (\(horizontalDistance)m)")
                }
                
                // Preserve small grade changes rather than zeroing them out
                // This ensures subtle elevation changes are still visible on the map
                // (Previously we were setting grades < 0.005 to 0.0)
                
                // Store the grade
                grades[i] = grade
                
                // Update max/min grade
                if i == 0 || grade > maxGrade {
                    maxGrade = grade
                }
                if i == 0 || grade < minGrade {
                    minGrade = grade
                }
            }
            
            // Still calculate ascent/descent point-to-point for accuracy
            if i > 0 {
                let elevationDiff = elevations[i] - elevations[i-1]
                // Only count significant elevation changes (>1m) to avoid noise
                if elevationDiff > 1.0 {
                    currentAscent += elevationDiff
                } else if elevationDiff < -1.0 {
                    currentDescent += abs(elevationDiff)
                }
            }
        }
        
        // Store final values
        totalAscent = currentAscent
        totalDescent = currentDescent
        
        // Set the last grade to match the previous to avoid gaps
        if grades.count > 1 {
            grades[grades.count - 1] = grades[grades.count - 2]
        }
    }
    
    // Smooth elevation data using a moving average
    private func smoothElevationData() {
        guard elevations.count > 3 else { return }
        
        // Create a copy of the original elevations
        let originalElevations = elevations
        
        // Window size for smoothing (adaptive to route length)
        let windowSize = min(5, elevations.count / 20 + 2)
        
        // Apply moving average smoothing
        for i in 0..<elevations.count {
            var sum: Double = 0
            var count: Double = 0
            
            // Calculate window boundaries
            let windowStart = max(0, i - windowSize)
            let windowEnd = min(originalElevations.count - 1, i + windowSize)
            
            // Sum elevations in window
            for j in windowStart...windowEnd {
                sum += originalElevations[j]
                count += 1
            }
            
            // Set smoothed elevation
            if count > 0 {
                elevations[i] = sum / count
            }
        }
    }
    
    // Helper method to get statistics formatted for display
    func getStatisticsDescription() -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        
        let ascentMeasurement = Measurement(value: totalAscent, unit: UnitLength.meters)
        let descentMeasurement = Measurement(value: totalDescent, unit: UnitLength.meters)
        
        let maxGradePercent = abs(maxGrade * 100)
        let minGradePercent = abs(minGrade * 100)
        
        return """
        Total Ascent: \(formatter.string(from: ascentMeasurement))
        Total Descent: \(formatter.string(from: descentMeasurement))
        Max Uphill Grade: \(String(format: "%.1f", maxGradePercent))%
        Max Downhill Grade: \(String(format: "%.1f", minGradePercent))%
        """
    }
}

// Original effort-based gradient polyline renderer
class GradientPolylineRenderer: MKPolylineRenderer {
    var elevationPolyline: ElevationPolyline?
    var callCounter: Int = 0
    
    // Constants for grade calculation - reduced to show more color variation
    private let minSignificantGrade: Double = 0.005  // 0.5% grade - flat/slight
    private let moderateGrade: Double = 0.03        // 3% grade - moderate
    private let steepGrade: Double = 0.08          // 8% grade - steep
    private let verysteepGrade: Double = 0.15      // 15% grade - very steep
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        guard let elevationPolyline = elevationPolyline else {
            super.draw(mapRect, zoomScale: zoomScale, in: ctx)
            return
        }

        // Start by getting the polyline's points in map coordinates
        let points = polyline.points()
        let pointCount = polyline.pointCount
        
        // We need at least 2 points to draw a line
        if pointCount < 2 {
            super.draw(mapRect, zoomScale: zoomScale, in: ctx)
            return
        }
        
        // Calculate line width with zoom adjustments
        let zoomAdjustedLineWidth = lineWidth / sqrt(zoomScale)
        let zoomBoostFactor = max(1.0, 0.2 / (zoomScale + 0.02))
        let actualLineWidth = min(zoomAdjustedLineWidth * zoomBoostFactor, lineWidth * 25)
        
        // Set up the context for drawing
        ctx.saveGState()
        ctx.setLineWidth(actualLineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        
        // Draw each segment with its corresponding color
        for i in 0..<(pointCount-1) {
            // Get map points for the segment
            let pointA = points[i]
            let pointB = points[i+1]
            
            // Convert to points in the renderer's coordinate system
            let pixelPointA = point(for: MKMapPoint(x: pointA.x, y: pointA.y))
            let pixelPointB = point(for: MKMapPoint(x: pointB.x, y: pointB.y))
            
            // Check if this segment is visible in the current map rect
            let segmentRect = MKMapRect(x: min(pointA.x, pointB.x),
                                       y: min(pointA.y, pointB.y),
                                       width: abs(pointB.x - pointA.x),
                                       height: abs(pointB.y - pointA.y))
            
            // Only draw if segment is visible
            if mapRect.intersects(segmentRect) {
                // Prevent out of bounds access
                let indexA = min(i, elevationPolyline.elevations.count - 1)
                let indexB = min(i+1, elevationPolyline.elevations.count - 1)
                
                // Get elevations at both points
                let elevationA = elevationPolyline.elevations[indexA]
                let elevationB = elevationPolyline.elevations[indexB]
                
                // Calculate the horizontal distance between points (in meters)
                let metersPerMapPoint = MKMetersPerMapPointAtLatitude(pointA.y)
                let dx = (pointB.x - pointA.x) * metersPerMapPoint
                let dy = (pointB.y - pointA.y) * metersPerMapPoint
                let horizontalDistance = sqrt(dx*dx + dy*dy)
                
                // Calculate grade (rise/run) if we have a significant horizontal distance
                var grade = 0.0
                
                // Try to use precomputed grades first if available
                if !elevationPolyline.grades.isEmpty && indexA < elevationPolyline.grades.count {
                    grade = elevationPolyline.grades[indexA]
                    //print("Segment \(i): Using precomputed grade: \(grade)")
                }
                // If grade is zero or grades aren't available, calculate it
                else if horizontalDistance > 1.0 {  // Avoid division by very small numbers
                    grade = (elevationB - elevationA) / horizontalDistance
                    
                    // Debug elevation info
                    //print("Segment \(i): elevA=\(elevationA), elevB=\(elevationB), diff=\(elevationB-elevationA), horizDist=\(horizontalDistance), rawGrade=\(grade)")
                    
                    // Filter out unrealistic grades from GPS noise
                    // Real-world roads/trails rarely exceed 30-35% grade
                    if abs(grade) > 0.5 {  // 50% grade cutoff for realism
                        // Apply a more reasonable limit
                        let oldGrade = grade
                        grade = grade > 0 ? 0.35 : -0.35
                        //print("  Clamping grade from \(oldGrade) to \(grade)")
                    }
                    
                    // Apply a minimum threshold to avoid flat line when elevation is changing
                    if abs(grade) < 0.01 && abs(elevationB - elevationA) > 0.5 {
                        grade = (elevationB > elevationA) ? 0.01 : -0.01
                        //print("  Boosting small grade to \(grade)")
                    }
                } else {
                    //print("Segment \(i): Horizontal distance too small (\(horizontalDistance)m), using grade=0")
                }
                
                // Apply color for this grade
                let color = colorForGrade(grade)
                
                // Set stroke color for this segment
                ctx.setStrokeColor(color.cgColor)
                
                // Draw the segment
                ctx.beginPath()
                ctx.move(to: pixelPointA)
                ctx.addLine(to: pixelPointB)
                ctx.strokePath()
            }
        }
        
        ctx.restoreGState()
    }
    
    // Get color based on grade (Garmin-like)
    private func colorForGrade(_ grade: Double) -> PlatformColor {
        // Ensure grade is in a reasonable range
        let clampedGrade = min(max(grade, -verysteepGrade), verysteepGrade)
        
        // Enable non-gray colors for flat sections
        // Set to true to show flat sections as colored
        let forceNonGrayColors = true
        
        // Only log every 10th call to avoid console flood
        var callCounter = self.callCounter
        callCounter += 1
        if callCounter % 20 == 0 {
            //print("colorForGrade call #\(callCounter): input: \(grade), clamped: \(clampedGrade)")
        }
        self.callCounter = callCounter
        
        // Color schemes based on Garmin's approach
        // Uphill: green to yellow to orange to red
        // Downhill: light blue to darker blue
        // Flat: gray
        
        if clampedGrade > 0 || (forceNonGrayColors && grade >= 0) {
            // Uphill or flat treated as slight uphill
            if clampedGrade < minSignificantGrade && !forceNonGrayColors {
                // Flat to slight uphill: gray (only if not forcing colors)
                return PlatformColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            } else if clampedGrade < moderateGrade {
                // Force more vibrant colors rather than subtle gradient
                // Use multiple distinct colors instead of blending
                
                // Slight uphill: vibrant green
                return PlatformColor(
                    red: 0.0,
                    green: 0.8,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if clampedGrade < steepGrade {
                // Moderate uphill: bright orange
                return PlatformColor(
                    red: 1.0,
                    green: 0.6,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if clampedGrade < verysteepGrade {
                // Steep uphill: bright red
                return PlatformColor(
                    red: 1.0,
                    green: 0.1,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else {
                // Very steep uphill: bright red
                return PlatformColor(red: 1.0, green: 0.1, blue: 0, alpha: 1.0)
            }
        } else {
            // Downhill (using absolute value of grade for calculations)
            let absGrade = abs(clampedGrade)
            
            if absGrade < minSignificantGrade && !forceNonGrayColors {
                // Flat to slight downhill: gray (only if not forcing colors)
                return PlatformColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            } else if absGrade < moderateGrade {
                // Light blue for slight downhill
                return PlatformColor(
                    red: 0.0,
                    green: 0.5,
                    blue: 1.0,
                    alpha: 1.0
                )
            } else if absGrade < steepGrade {
                // Medium blue for moderate downhill
                return PlatformColor(
                    red: 0.0,
                    green: 0.3,
                    blue: 0.9,
                    alpha: 1.0
                )
            } else if absGrade < verysteepGrade {
                // Deep blue/purple for steep downhill
                return PlatformColor(
                    red: 0.3,
                    green: 0.0,
                    blue: 0.8,
                    alpha: 1.0
                )
            } else {
                // Very steep downhill: purple
                return PlatformColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 1.0)
            }
        }
    }
}

// New pure elevation gradient polyline renderer
class ElevationGradientPolylineRenderer: MKPolylineRenderer {
    var elevationPolyline: ElevationPolyline?
    var callCounter: Int = 0
    
    // Constants for color range
    private let minSignificantValue: Double = 0.05  // 5% of range - slight color change
    private let moderateValue: Double = 0.3        // 30% of range - moderate color change
    private let strongValue: Double = 0.6          // 60% of range - strong color change
    private let extremeValue: Double = 0.85        // 85% of range - extreme color change
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        guard let elevationPolyline = elevationPolyline else {
            super.draw(mapRect, zoomScale: zoomScale, in: ctx)
            return
        }

        // Start by getting the polyline's points in map coordinates
        let points = polyline.points()
        let pointCount = polyline.pointCount
        
        // We need at least 2 points to draw a line
        if pointCount < 2 {
            super.draw(mapRect, zoomScale: zoomScale, in: ctx)
            return
        }
        
        // Calculate line width with zoom adjustments
        let zoomAdjustedLineWidth = lineWidth / sqrt(zoomScale)
        let zoomBoostFactor = max(1.0, 0.2 / (zoomScale + 0.02))
        let actualLineWidth = min(zoomAdjustedLineWidth * zoomBoostFactor, lineWidth * 25)
        
        // Set up the context for drawing
        ctx.saveGState()
        ctx.setLineWidth(actualLineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        
        // Draw each segment with its corresponding color
        for i in 0..<(pointCount-1) {
            // Get map points for the segment
            let pointA = points[i]
            let pointB = points[i+1]
            
            // Convert to points in the renderer's coordinate system
            let pixelPointA = point(for: MKMapPoint(x: pointA.x, y: pointA.y))
            let pixelPointB = point(for: MKMapPoint(x: pointB.x, y: pointB.y))
            
            // Check if this segment is visible in the current map rect
            let segmentRect = MKMapRect(x: min(pointA.x, pointB.x),
                                       y: min(pointA.y, pointB.y),
                                       width: abs(pointB.x - pointA.x),
                                       height: abs(pointB.y - pointA.y))
            
            // Only draw if segment is visible
            if mapRect.intersects(segmentRect) {
                // Prevent out of bounds access
                let indexA = min(i, elevationPolyline.elevations.count - 1)
                
                // Get current elevation
                let elevation = elevationPolyline.elevations[indexA]
                
                // Calculate normalized elevation (0 to 1 scale)
                var normalizedElevation = 0.5 // Default to middle (gray) if no elevation range
                
                if elevationPolyline.maxElevation > elevationPolyline.minElevation {
                    normalizedElevation = (elevation - elevationPolyline.minElevation) / 
                                         (elevationPolyline.maxElevation - elevationPolyline.minElevation)
                }
                
                // Get color based on normalized elevation
                let color = colorForNormalizedElevation(normalizedElevation)
                
                // Set stroke color for this segment
                ctx.setStrokeColor(color.cgColor)
                
                // Draw the segment
                ctx.beginPath()
                ctx.move(to: pixelPointA)
                ctx.addLine(to: pixelPointB)
                ctx.strokePath()
            }
        }
        
        ctx.restoreGState()
    }
    
    // Get color based on normalized elevation (0-1 scale)
    private func colorForNormalizedElevation(_ value: Double) -> PlatformColor {
        // Ensure value is in 0-1 range
        let clampedValue = min(max(value, 0.0), 1.0)
        
        // Only log every 10th call to avoid console flood
        var callCounter = self.callCounter
        callCounter += 1
        if callCounter % 20 == 0 {
            //print("colorForNormalizedElevation call #\(callCounter): input: \(value), clamped: \(clampedValue)")
        }
        self.callCounter = callCounter
        
        // Color scheme for elevation:
        // Low: Deep blue -> Medium blue -> Light blue
        // Middle: Green/Yellow
        // High: Yellow -> Orange -> Red
        
        if clampedValue < 0.5 {
            // Lower half of elevation range (0.0-0.5 mapped to 0.0-1.0)
            let scaledValue = clampedValue * 2 // Scale to 0-1 range
            
            if scaledValue < minSignificantValue {
                // Deepest blue - lowest elevation
                return PlatformColor(
                    red: 0.0,
                    green: 0.0,
                    blue: 0.8,
                    alpha: 1.0
                )
            } else if scaledValue < moderateValue {
                // Medium blue
                return PlatformColor(
                    red: 0.0,
                    green: 0.3,
                    blue: 0.9,
                    alpha: 1.0
                )
            } else if scaledValue < strongValue {
                // Light blue
                return PlatformColor(
                    red: 0.0,
                    green: 0.6,
                    blue: 1.0,
                    alpha: 1.0
                )
            } else {
                // Cyan - approaching middle elevation
                return PlatformColor(
                    red: 0.0,
                    green: 0.8,
                    blue: 0.8,
                    alpha: 1.0
                )
            }
        } else {
            // Upper half of elevation range (0.5-1.0 mapped to 0.0-1.0)
            let scaledValue = (clampedValue - 0.5) * 2 // Scale to 0-1 range
            
            if scaledValue < minSignificantValue {
                // Green - just above middle elevation
                return PlatformColor(
                    red: 0.1,
                    green: 0.8,
                    blue: 0.1,
                    alpha: 1.0
                )
            } else if scaledValue < moderateValue {
                // Yellow-green
                return PlatformColor(
                    red: 0.6,
                    green: 0.8,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if scaledValue < strongValue {
                // Yellow/orange
                return PlatformColor(
                    red: 1.0,
                    green: 0.6,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else if scaledValue < extremeValue {
                // Orange/red - high elevation
                return PlatformColor(
                    red: 1.0,
                    green: 0.3,
                    blue: 0.0,
                    alpha: 1.0
                )
            } else {
                // Bright red - highest elevation
                return PlatformColor(
                    red: 1.0,
                    green: 0.0,
                    blue: 0.0,
                    alpha: 1.0
                )
            }
        }
    }
}

#if os(iOS)
struct MapView: UIViewRepresentable {
    let trackSegments: [GPXTrackSegment]
    let waypoints: [GPXWaypoint]
    @EnvironmentObject var settings: SettingsModel
    
    // Optional center point for when a waypoint is selected from the drawer
    var centerCoordinate: CLLocationCoordinate2D?
    var zoomLevel: Double? // Optional zoom level, default will be used if nil
    var spanAll: Bool = false // Trigger to span the view to show all content
    
    // Convenience init to maintain backward compatibility
    init(routeLocations: [CLLocation]) {
        self.trackSegments = [GPXTrackSegment(locations: routeLocations, trackIndex: 0)]
        self.waypoints = []
        self.centerCoordinate = nil
        self.zoomLevel = nil
        self.spanAll = false
    }
    
    // New initializer for multiple segments
    init(trackSegments: [GPXTrackSegment]) {
        self.trackSegments = trackSegments
        self.waypoints = []
        self.centerCoordinate = nil
        self.zoomLevel = nil
        self.spanAll = false
    }
    
    // New initializer for segments and waypoints
    init(trackSegments: [GPXTrackSegment], waypoints: [GPXWaypoint]) {
        self.trackSegments = trackSegments
        self.waypoints = waypoints
        self.centerCoordinate = nil
        self.zoomLevel = nil
        self.spanAll = false
    }
    
    // New initializer for centering on a specific waypoint
    init(trackSegments: [GPXTrackSegment], waypoints: [GPXWaypoint], centerCoordinate: CLLocationCoordinate2D?, zoomLevel: Double? = nil, spanAll: Bool = false) {
        self.trackSegments = trackSegments
        self.waypoints = waypoints
        self.centerCoordinate = centerCoordinate
        self.zoomLevel = zoomLevel
        self.spanAll = spanAll
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        
        // Store if this is initial load to perform delayed zoom in
        context.coordinator.isInitialLoad = true
        
        #if swift(>=5.7) && !targetEnvironment(macCatalyst)
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
        } else {
            mapView.mapType = settings.mapStyle.mapType
        }
        #else
        mapView.mapType = settings.mapStyle.mapType
        #endif
        
        // Skip if no segments
        if trackSegments.isEmpty {
            return mapView
        }
        
        // Collect all locations for region setting
        var allLocations: [CLLocation] = []
        
        // Store all polylines for the coordinator
        var elevationPolylines: [ElevationPolyline] = []
        
        // Process each segment separately
        for (index, segment) in trackSegments.enumerated() {
            let locations = segment.locations
            guard !locations.isEmpty else { continue }
            
            // Add locations for region calculation later
            allLocations.append(contentsOf: locations)
            
            // Create the enhanced elevation polyline for this segment
            let elevationPolyline = createElevationPolyline(from: locations)
            
            // Calculate grade data (this will smooth and process elevation data)
            elevationPolyline.calculateGradeData(from: locations)
            
            // Debug elevation data
            print("=== SEGMENT \(index+1) ELEVATION DATA SUMMARY ===")
            print("Total points: \(elevationPolyline.elevations.count)")
            print("Min elevation: \(elevationPolyline.minElevation)m")
            print("Max elevation: \(elevationPolyline.maxElevation)m")
            print("Total ascent: \(elevationPolyline.totalAscent)m")
            print("Total descent: \(elevationPolyline.totalDescent)m")
            print("Grade range: \(elevationPolyline.minGrade) to \(elevationPolyline.maxGrade)")
            if !elevationPolyline.grades.isEmpty {
                let nonZeroGrades = elevationPolyline.grades.filter { abs($0) > 0.005 }
                print("Non-zero grades count: \(nonZeroGrades.count) of \(elevationPolyline.grades.count)")
                
                // Sample some grades
                if nonZeroGrades.count > 0 {
                    let sampleCount = min(5, nonZeroGrades.count)
                    print("Sample grades: \(nonZeroGrades.prefix(sampleCount))")
                }
            }
            print("==============================")
            
            // Add to map
            mapView.addOverlay(elevationPolyline)
            
            // Store the polyline for the coordinator
            elevationPolylines.append(elevationPolyline)
        }
        
        // Store elevation polylines in coordinator for renderer to use
        context.coordinator.elevationPolylines = elevationPolylines
        
        // Set the visible region to show all tracks
        if !allLocations.isEmpty {
            // Add significant elevation markers (Garmin-like)
            addElevationMarkers(to: mapView, routeLocations: allLocations)
            
            // Set the region to show all segments
            MapView.setRegion(for: mapView, from: allLocations)
            
            // Add start and end annotations using the first and last segments
            if let firstSegment = trackSegments.first, 
               let lastSegment = trackSegments.last,
               let firstLocation = firstSegment.locations.first,
               let lastLocation = lastSegment.locations.last {
                
                let startPoint = MKPointAnnotation()
                startPoint.coordinate = firstLocation.coordinate
                startPoint.title = "Start"
                
                let endPoint = MKPointAnnotation()
                endPoint.coordinate = lastLocation.coordinate
                endPoint.title = "End"
                
                mapView.addAnnotations([startPoint, endPoint])
            }
            
            // Add waypoint annotations
            if !waypoints.isEmpty {
                let waypointAnnotations = waypoints.map { WaypointAnnotation(waypoint: $0) }
                mapView.addAnnotations(waypointAnnotations)
                print("Added \(waypointAnnotations.count) waypoint annotations to map")
            }
            
            // Store the locations for delayed zoom (this will be applied in updateUIView)
            context.coordinator.initialLoadLocations = allLocations
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update map configuration if settings changed
        #if swift(>=5.7) && !targetEnvironment(macCatalyst)
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
        } else {
            mapView.mapType = settings.mapStyle.mapType
        }
        #else
        mapView.mapType = settings.mapStyle.mapType
        #endif
        
        // Always update when this method is called to ensure visibility changes are reflected
        // This handles both segment count changes and visibility toggling
        
        // Get existing overlays before clearing
        let existingOverlaysCount = mapView.overlays.count
        
        // Clear existing overlays and annotations
        context.coordinator.clearOverlays(from: mapView)
        mapView.removeAnnotations(mapView.annotations)
        
        // Skip if no segments to show
        if trackSegments.isEmpty && waypoints.isEmpty {
            context.coordinator.elevationPolylines = []
            return
        }
        
        // Add each segment's polyline
        var newElevationPolylines: [ElevationPolyline] = []
        for segment in trackSegments {
            let elevationPolyline = createElevationPolyline(from: segment.locations)
            elevationPolyline.calculateGradeData(from: segment.locations)
            mapView.addOverlay(elevationPolyline)
            newElevationPolylines.append(elevationPolyline)
        }
        
        // Update the coordinator's polylines
        context.coordinator.elevationPolylines = newElevationPolylines
        
        // Collect all locations
        let allLocations = trackSegments.flatMap { $0.locations }
        
        // Add waypoint annotations
        var waypointAnnotations: [WaypointAnnotation] = []
        if !waypoints.isEmpty {
            waypointAnnotations = waypoints.map { WaypointAnnotation(waypoint: $0) }
            mapView.addAnnotations(waypointAnnotations)
        }
        
        if !allLocations.isEmpty {
            // Add elevation markers
            addElevationMarkers(to: mapView, routeLocations: allLocations)
            
            // Add start and end annotations
            if let firstSegment = trackSegments.first, 
               let lastSegment = trackSegments.last,
               let firstLocation = firstSegment.locations.first,
               let lastLocation = lastSegment.locations.last {
                
                let startPoint = MKPointAnnotation()
                startPoint.coordinate = firstLocation.coordinate
                startPoint.title = "Start"
                
                let endPoint = MKPointAnnotation()
                endPoint.coordinate = lastLocation.coordinate
                endPoint.title = "End"
                
                mapView.addAnnotations([startPoint, endPoint])
            }
        }
        
        // Check if we need to center on a specific waypoint
        if let center = centerCoordinate {
            // Center the map on the specified coordinate with animation
            let span = MKCoordinateSpan(
                latitudeDelta: zoomLevel ?? 0.01,  // Default zoom if not specified
                longitudeDelta: zoomLevel ?? 0.01
            )
            let region = MKCoordinateRegion(center: center, span: span)
            mapView.setRegion(region, animated: true)
            
            // Highlight the selected waypoint if it exists
            if let waypointAnnotation = waypointAnnotations.first(where: { 
                $0.coordinate.latitude == center.latitude && 
                $0.coordinate.longitude == center.longitude 
            }) {
                // Select the annotation to show its callout
                mapView.selectAnnotation(waypointAnnotation, animated: true)
            }
        }
        // Check if we need to span to show all content
        else if spanAll {
            // Combine all track locations and waypoints
            var allLocations = trackSegments.flatMap { $0.locations }
            
            // Add waypoint locations if there are any
            if !waypoints.isEmpty {
                let waypointLocations = waypoints.map { 
                    CLLocation(
                        coordinate: $0.coordinate, 
                        altitude: $0.elevation ?? 0,
                        horizontalAccuracy: 10,
                        verticalAccuracy: 10,
                        timestamp: $0.timestamp ?? Date()
                    )
                }
                allLocations.append(contentsOf: waypointLocations)
            }
            
            if !allLocations.isEmpty {
                // Set region to fit everything with animation
                MapView.setRegion(for: mapView, from: allLocations)
                
                // Add a slight delay to ensure the map has time to process the region change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    // Apply a slight animation to make the zoom more smooth
                    UIView.animate(withDuration: 0.3) {
                        mapView.setRegion(mapView.region, animated: false)
                    }
                }
            }
        }
        // Otherwise handle normal region setting
        else if context.coordinator.isInitialLoad {
            // Collect all locations
            if !allLocations.isEmpty {
                print("Setting up delayed zoom for initial load")
                context.coordinator.performDelayedZoom(mapView: mapView, locations: allLocations)
            }
        } 
        // Regular region setting (for cases other than initial load)
        else {
            // Adjust the map view region in these cases:
            // 1. First time showing segments (existingOverlaysCount == 0)
            // 2. When showing tracks after they were hidden (existingOverlaysCount != newElevationPolylines.count)
            // 3. Always set region on iOS to ensure consistent behavior
            let shouldSetRegion = (!newElevationPolylines.isEmpty && 
                                 (existingOverlaysCount == 0 || 
                                  existingOverlaysCount != newElevationPolylines.count))
                                 || (newElevationPolylines.isEmpty && !waypoints.isEmpty)
            
            if shouldSetRegion {
                if !allLocations.isEmpty {
                    // Set the map region to fit all visible segments
                    MapView.setRegion(for: mapView, from: allLocations)
                } else if !waypoints.isEmpty {
                    // If we only have waypoints, set region to show all waypoints
                    let waypointLocations = waypoints.map { 
                        CLLocation(
                            coordinate: $0.coordinate, 
                            altitude: $0.elevation ?? 0,
                            horizontalAccuracy: 10,
                            verticalAccuracy: 10,
                            timestamp: $0.timestamp ?? Date()
                        )
                    }
                    MapView.setRegion(for: mapView, from: waypointLocations)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
#else
struct MapView: NSViewRepresentable {
    let trackSegments: [GPXTrackSegment]
    let waypoints: [GPXWaypoint]
    @EnvironmentObject var settings: SettingsModel
    
    // Optional center point for when a waypoint is selected from the drawer
    var centerCoordinate: CLLocationCoordinate2D?
    var zoomLevel: Double? // Optional zoom level, default will be used if nil
    var spanAll: Bool = false // Trigger to span the view to show all content
    
    // Convenience init to maintain backward compatibility
    init(routeLocations: [CLLocation]) {
        self.trackSegments = [GPXTrackSegment(locations: routeLocations, trackIndex: 0)]
        self.waypoints = []
        self.centerCoordinate = nil
        self.zoomLevel = nil
        self.spanAll = false
    }
    
    // New initializer for multiple segments
    init(trackSegments: [GPXTrackSegment]) {
        self.trackSegments = trackSegments
        self.waypoints = []
        self.centerCoordinate = nil
        self.zoomLevel = nil
        self.spanAll = false
    }
    
    // New initializer for segments and waypoints
    init(trackSegments: [GPXTrackSegment], waypoints: [GPXWaypoint]) {
        self.trackSegments = trackSegments
        self.waypoints = waypoints
        self.centerCoordinate = nil
        self.zoomLevel = nil
        self.spanAll = false
    }
    
    // New initializer for centering on a specific waypoint
    init(trackSegments: [GPXTrackSegment], waypoints: [GPXWaypoint], centerCoordinate: CLLocationCoordinate2D?, zoomLevel: Double? = nil, spanAll: Bool = false) {
        self.trackSegments = trackSegments
        self.waypoints = waypoints
        self.centerCoordinate = centerCoordinate
        self.zoomLevel = zoomLevel
        self.spanAll = spanAll
    }
    
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        
        #if swift(>=5.7)
        if #available(macOS 13.0, *) {
            mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
        } else {
            mapView.mapType = settings.mapStyle.mapType
        }
        #else
        mapView.mapType = settings.mapStyle.mapType
        #endif
        
        // Skip if no segments
        if trackSegments.isEmpty {
            return mapView
        }
        
        // Collect all locations for region setting
        var allLocations: [CLLocation] = []
        
        // Store all polylines for the coordinator
        var elevationPolylines: [ElevationPolyline] = []
        
        // Process each segment separately
        for (index, segment) in trackSegments.enumerated() {
            let locations = segment.locations
            guard !locations.isEmpty else { continue }
            
            // Add locations for region calculation later
            allLocations.append(contentsOf: locations)
            
            // Create the enhanced elevation polyline for this segment
            let elevationPolyline = createElevationPolyline(from: locations)
            
            // Calculate grade data (this will smooth and process elevation data)
            elevationPolyline.calculateGradeData(from: locations)
            
            // Debug elevation data
            print("=== SEGMENT \(index+1) ELEVATION DATA SUMMARY ===")
            print("Total points: \(elevationPolyline.elevations.count)")
            print("Min elevation: \(elevationPolyline.minElevation)m")
            print("Max elevation: \(elevationPolyline.maxElevation)m")
            print("Total ascent: \(elevationPolyline.totalAscent)m")
            print("Total descent: \(elevationPolyline.totalDescent)m")
            print("Grade range: \(elevationPolyline.minGrade) to \(elevationPolyline.maxGrade)")
            if !elevationPolyline.grades.isEmpty {
                let nonZeroGrades = elevationPolyline.grades.filter { abs($0) > 0.005 }
                print("Non-zero grades count: \(nonZeroGrades.count) of \(elevationPolyline.grades.count)")
                
                // Sample some grades
                if nonZeroGrades.count > 0 {
                    let sampleCount = min(5, nonZeroGrades.count)
                    print("Sample grades: \(nonZeroGrades.prefix(sampleCount))")
                }
            }
            print("==============================")
            
            // Add to map
            mapView.addOverlay(elevationPolyline)
            
            // Store the polyline for the coordinator
            elevationPolylines.append(elevationPolyline)
        }
        
        // Store elevation polylines in coordinator for renderer to use
        context.coordinator.elevationPolylines = elevationPolylines
        
        // Set the visible region to show all tracks
        if !allLocations.isEmpty {
            // Add significant elevation markers (Garmin-like)
            addElevationMarkers(to: mapView, routeLocations: allLocations)
            
            // Set the region to show all segments
            MapView.setRegion(for: mapView, from: allLocations)
            
            // Add start and end annotations using the first and last segments
            if let firstSegment = trackSegments.first, 
               let lastSegment = trackSegments.last,
               let firstLocation = firstSegment.locations.first,
               let lastLocation = lastSegment.locations.last {
                
                let startPoint = MKPointAnnotation()
                startPoint.coordinate = firstLocation.coordinate
                startPoint.title = "Start"
                
                let endPoint = MKPointAnnotation()
                endPoint.coordinate = lastLocation.coordinate
                endPoint.title = "End"
                
                mapView.addAnnotations([startPoint, endPoint])
            }
            
            // Add waypoint annotations
            if !waypoints.isEmpty {
                let waypointAnnotations = waypoints.map { WaypointAnnotation(waypoint: $0) }
                mapView.addAnnotations(waypointAnnotations)
                print("Added \(waypointAnnotations.count) waypoint annotations to map")
            }
        }
        
        return mapView
    }
    
    func updateNSView(_ mapView: MKMapView, context: Context) {
        // Update map configuration if settings changed
        #if swift(>=5.7)
        if #available(macOS 13.0, *) {
            mapView.preferredConfiguration = settings.mapStyle.mapConfiguration
        } else {
            mapView.mapType = settings.mapStyle.mapType
        }
        #else
        mapView.mapType = settings.mapStyle.mapType
        #endif
        
        // Always update when this method is called to ensure visibility changes are reflected
        // This handles both segment count changes and visibility toggling
        
        // Get existing overlays before clearing
        let existingOverlaysCount = mapView.overlays.count
        
        // Clear existing overlays and annotations
        context.coordinator.clearOverlays(from: mapView)
        mapView.removeAnnotations(mapView.annotations)
        
        // Skip if no segments or waypoints to show
        if trackSegments.isEmpty && waypoints.isEmpty {
            context.coordinator.elevationPolylines = []
            return
        }
        
        // Add each segment's polyline
        var newElevationPolylines: [ElevationPolyline] = []
        for segment in trackSegments {
            let elevationPolyline = createElevationPolyline(from: segment.locations)
            elevationPolyline.calculateGradeData(from: segment.locations)
            mapView.addOverlay(elevationPolyline)
            newElevationPolylines.append(elevationPolyline)
        }
        
        // Update the coordinator's polylines
        context.coordinator.elevationPolylines = newElevationPolylines
        
        // Collect all locations
        let allLocations = trackSegments.flatMap { $0.locations }
        
        // Add waypoint annotations
        var waypointAnnotations: [WaypointAnnotation] = []
        if !waypoints.isEmpty {
            waypointAnnotations = waypoints.map { WaypointAnnotation(waypoint: $0) }
            mapView.addAnnotations(waypointAnnotations)
        }
        
        if !allLocations.isEmpty {
            // Add elevation markers
            addElevationMarkers(to: mapView, routeLocations: allLocations)
            
            // Add start and end annotations
            if let firstSegment = trackSegments.first, 
               let lastSegment = trackSegments.last,
               let firstLocation = firstSegment.locations.first,
               let lastLocation = lastSegment.locations.last {
                
                let startPoint = MKPointAnnotation()
                startPoint.coordinate = firstLocation.coordinate
                startPoint.title = "Start"
                
                let endPoint = MKPointAnnotation()
                endPoint.coordinate = lastLocation.coordinate
                endPoint.title = "End"
                
                mapView.addAnnotations([startPoint, endPoint])
            }
        }
        
        // Check if we need to center on a specific waypoint
        if let center = centerCoordinate {
            // Center the map on the specified coordinate with animation
            let span = MKCoordinateSpan(
                latitudeDelta: zoomLevel ?? 0.01,  // Default zoom if not specified
                longitudeDelta: zoomLevel ?? 0.01
            )
            let region = MKCoordinateRegion(center: center, span: span)
            mapView.setRegion(region, animated: true)
            
            // Highlight the selected waypoint if it exists
            if let waypointAnnotation = waypointAnnotations.first(where: { 
                $0.coordinate.latitude == center.latitude && 
                $0.coordinate.longitude == center.longitude 
            }) {
                // Select the annotation to show its callout
                mapView.selectAnnotation(waypointAnnotation, animated: true)
            }
        }
        // Check if we need to span to show all content
        else if spanAll {
            // Combine all track locations and waypoints
            var allLocations = trackSegments.flatMap { $0.locations }
            
            // Add waypoint locations if there are any
            if !waypoints.isEmpty {
                let waypointLocations = waypoints.map { 
                    CLLocation(
                        coordinate: $0.coordinate, 
                        altitude: $0.elevation ?? 0,
                        horizontalAccuracy: 10,
                        verticalAccuracy: 10,
                        timestamp: $0.timestamp ?? Date()
                    )
                }
                allLocations.append(contentsOf: waypointLocations)
            }
            
            if !allLocations.isEmpty {
                // Set region to fit everything with animation
                MapView.setRegion(for: mapView, from: allLocations)
                
                // Add a slight delay to ensure the map has time to process the region change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    // Apply a slight animation to make the zoom more smooth
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.3
                        mapView.setRegion(mapView.region, animated: false)
                    }
                }
            }
        }
        // Otherwise handle normal region setting
        else {
            // Adjust the map view region in these cases:
            // 1. First time showing segments (existingOverlaysCount == 0)
            // 2. When showing tracks after they were hidden (existingOverlaysCount != newElevationPolylines.count)
            let shouldSetRegion = (!newElevationPolylines.isEmpty && 
                                 (existingOverlaysCount == 0 || 
                                  existingOverlaysCount != newElevationPolylines.count))
                                 || (newElevationPolylines.isEmpty && !waypoints.isEmpty)
            
            if shouldSetRegion {
                if !allLocations.isEmpty {
                    // Set the map region to fit all visible segments
                    MapView.setRegion(for: mapView, from: allLocations)
                } else if !waypoints.isEmpty {
                    // If we only have waypoints, set region to show all waypoints
                    let waypointLocations = waypoints.map { 
                        CLLocation(
                            coordinate: $0.coordinate, 
                            altitude: $0.elevation ?? 0,
                            horizontalAccuracy: 10,
                            verticalAccuracy: 10,
                            timestamp: $0.timestamp ?? Date()
                        )
                    }
                    MapView.setRegion(for: mapView, from: waypointLocations)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
}
#endif
    
#if os(iOS) || os(macOS)

// Custom annotation for waypoints
class WaypointAnnotation: NSObject, MKAnnotation {
    let waypoint: GPXWaypoint
    var _subtitle: String?
    
    var coordinate: CLLocationCoordinate2D {
        return waypoint.coordinate
    }
    
    var title: String? {
        return waypoint.name
    }
    
    var subtitle: String? {
        // Return custom subtitle if set, otherwise fallback to waypoint description
        return _subtitle ?? waypoint.description
    }
    
    init(waypoint: GPXWaypoint) {
        self.waypoint = waypoint
        super.init()
        
        // Subtitle will be set in the mapView(_:viewFor:) method
        // We don't set default values here to allow the view to determine them
    }
}

// Helper functions shared by both platforms
extension MapView {
    func createElevationPolyline(from locations: [CLLocation]) -> ElevationPolyline {
        let coordinates = locations.map { $0.coordinate }
        let elevations = locations.map { $0.altitude }
        
        // Create the polyline with coordinates
        let elevationPolyline = ElevationPolyline(coordinates: coordinates, count: coordinates.count)
        
        // Store the elevations
        elevationPolyline.elevations = elevations
        
        // Calculate min and max elevations for scaling the gradient
        if let minEle = elevations.min(), let maxEle = elevations.max() {
            elevationPolyline.minElevation = minEle
            elevationPolyline.maxElevation = maxEle
        }
        
        return elevationPolyline
    }
    
    func addElevationMarkers(to mapView: MKMapView, routeLocations: [CLLocation]) {
        guard routeLocations.count > 10 else { return }
        
        let elevations = routeLocations.map { $0.altitude }
        
        // Find local maxima and minima that are significant
        var significantPoints: [(index: Int, elevation: Double, isMax: Bool)] = []
        let windowSize = max(routeLocations.count / 20, 5) // Adaptive window size
        
        for i in windowSize..<(routeLocations.count - windowSize) {
            let currentElev = elevations[i]
            
            // Check if this is a local maximum
            var isLocalMax = true
            for j in (i-windowSize)...(i+windowSize) {
                if j != i && elevations[j] > currentElev {
                    isLocalMax = false
                    break
                }
            }
            
            // Check if this is a local minimum
            var isLocalMin = true
            for j in (i-windowSize)...(i+windowSize) {
                if j != i && elevations[j] < currentElev {
                    isLocalMin = false
                    break
                }
            }
            
            // Only add points that are significantly different from their surroundings
            if isLocalMax || isLocalMin {
                // Calculate average elevation in the window
                var sum = 0.0
                for j in (i-windowSize)...(i+windowSize) {
                    sum += elevations[j]
                }
                let avgElev = sum / Double(2 * windowSize + 1)
                
                // Check if the difference is significant (>= 10 meters)
                let elevDiff = abs(currentElev - avgElev)
                if elevDiff >= 10 {
                    significantPoints.append((i, currentElev, isLocalMax))
                }
            }
        }
        
        // Add elevation markers for significant points (limit to avoid clutter)
        let maxMarkers = 5
        if significantPoints.count > maxMarkers {
            // Sort by elevation difference and take top ones
            significantPoints.sort { abs($0.elevation) > abs($1.elevation) }
            significantPoints = Array(significantPoints.prefix(maxMarkers))
        }
        
        // Create annotations for these points
        for point in significantPoints {
            let annotation = MKPointAnnotation()
            annotation.coordinate = routeLocations[point.index].coordinate
            
            let elevationFormatted = Int(round(point.elevation))
            annotation.title = point.isMax ? "Peak" : "Valley"
            annotation.subtitle = "\(elevationFormatted)m"
            
            mapView.addAnnotation(annotation)
        }
    }
    
    public static func setRegion(for mapView: MKMapView, from locations: [CLLocation]) {
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
#endif
    
// Shared Coordinator class that can be used with both UIViewRepresentable and NSViewRepresentable
class Coordinator: NSObject, MKMapViewDelegate {
    var elevationPolylines: [ElevationPolyline] = []
    var isInitialLoad: Bool = false
    var initialLoadLocations: [CLLocation]? = nil
    var delayedZoomTimer: Timer? = nil
    
    // Keep the single polyline property for backward compatibility
    var elevationPolyline: ElevationPolyline? {
        get {
            return elevationPolylines.first
        }
        set {
            if let newValue = newValue {
                elevationPolylines = [newValue]
            } else {
                elevationPolylines = []
            }
        }
    }
    
    // Clear all overlays from the map
    func clearOverlays(from mapView: MKMapView) {
        mapView.removeOverlays(mapView.overlays)
    }
    
    // Perform a delayed zoom for initial load (iOS only)
#if os(iOS)
    func performDelayedZoom(mapView: MKMapView, locations: [CLLocation]) {
        // Cancel any existing timer
        delayedZoomTimer?.invalidate()
        
        // Setup a timer to perform the delayed zoom (500ms delay)
        delayedZoomTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            print("Performing delayed zoom after initial load")
            
            MapView.setRegion(for: mapView, from: locations)
            
            // Reset initial load flag
            self.isInitialLoad = false
            self.initialLoadLocations = nil
        }
    }
#endif
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? ElevationPolyline {
            // Get settings from the MapView through the coordinator
            guard let modeString = UserDefaults.standard.string(forKey: "elevationVisualizationMode"),
                  let mode = ElevationVisualizationMode(rawValue: modeString) else {
                // Default to effort if setting not found
                let gradientRenderer = GradientPolylineRenderer(polyline: polyline)
                gradientRenderer.elevationPolyline = polyline
                gradientRenderer.lineWidth = 12  // Increased line width for better visibility
                return gradientRenderer
            }
            
            // Select renderer based on the visualization mode
            switch mode {
            case .effort:
                // Create original effort-based gradient polyline renderer
                let gradientRenderer = GradientPolylineRenderer(polyline: polyline)
                gradientRenderer.elevationPolyline = polyline
                gradientRenderer.lineWidth = 12  // Increased line width for better visibility
                return gradientRenderer
                
            case .gradient:
                // Create pure elevation gradient polyline renderer
                let elevationRenderer = ElevationGradientPolylineRenderer(polyline: polyline)
                elevationRenderer.elevationPolyline = polyline
                elevationRenderer.lineWidth = 12  // Increased line width for better visibility
                return elevationRenderer
            }
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard !annotation.isKind(of: MKUserLocation.self) else { return nil }
        
        // Use a different identifier for waypoints
        let identifier = annotation is WaypointAnnotation ? "WaypointPin" : "WorkoutPin"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
        } else {
            annotationView?.annotation = annotation
        }
        
        if let markerView = annotationView as? MKMarkerAnnotationView {
            // Handle waypoint annotations
            if let waypointAnnotation = annotation as? WaypointAnnotation {
                markerView.markerTintColor = .purple
#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "mappin")
                // Add a button for copying coordinates
                let button = UIButton(type: .custom)
                button.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
                button.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
                button.tintColor = UIColor.systemBlue
                annotationView?.rightCalloutAccessoryView = button
#elseif os(macOS)
                // Use SF Symbols on macOS 11+
                if #available(macOS 11.0, *) {
                    markerView.glyphImage = NSImage(systemSymbolName: "mappin", accessibilityDescription: "Waypoint")
                } else {
                    // Fallback for older macOS versions
                    markerView.glyphText = "W"
                }
                // Add a button for copying coordinates on macOS
                let button = NSButton(title: "Copy", target: nil, action: nil)
                button.bezelStyle = .rounded
                annotationView?.rightCalloutAccessoryView = button
#endif
                
                // Set subtitle based on waypoint description if available, otherwise use coordinates
                if let description = waypointAnnotation.waypoint.description, !description.isEmpty {
                    waypointAnnotation._subtitle = description
                } else {
                    // Fallback to coordinates if no description
                    let coordinate = waypointAnnotation.coordinate
                    let lat = String(format: "%.6f", coordinate.latitude)
                    let lon = String(format: "%.6f", coordinate.longitude)
                    waypointAnnotation._subtitle = "\(lat), \(lon)"
                }
                
                // Use custom glyph based on waypoint symbol if available
                if let symbol = waypointAnnotation.waypoint.symbol {
                    // Common GPX symbols can be mapped to SF Symbols
                    let iconName: String
                    switch symbol.lowercased() {
                    case "flag", "summit":
                        iconName = "flag"
                    case "campground", "camp":
                        iconName = "tent"
                    case "water", "drinking-water":
                        iconName = "drop"
                    case "parking":
                        iconName = "car"
                    case "info", "information":
                        iconName = "info.circle"
                    case "danger", "caution":
                        iconName = "exclamationmark.triangle"
                    case "restaurant", "food":
                        iconName = "fork.knife"
                    default:
                        iconName = "mappin"
                    }
                    
#if os(iOS)
                    markerView.glyphImage = UIImage(systemName: iconName)
#elseif os(macOS)
                    if #available(macOS 11.0, *) {
                        markerView.glyphImage = NSImage(systemSymbolName: iconName, accessibilityDescription: symbol)
                    }
#endif
                }
                
                // Set priority for waypoints (higher than elevation markers)
                markerView.displayPriority = .defaultHigh
            }
            // Set appearance based on annotation type for track markers
            else if annotation.title == "Start" {
                markerView.markerTintColor = .green
#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "flag.fill")
#elseif os(macOS)
                // Use SF Symbols on macOS 11+
                if #available(macOS 11.0, *) {
                    markerView.glyphImage = NSImage(systemSymbolName: "flag.fill", accessibilityDescription: "Start")
                } else {
                    // Fallback for older macOS versions
                    markerView.glyphText = "S"
                }
#endif
            } else if annotation.title == "End" {
                markerView.markerTintColor = .red
#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "flag.checkered")
#elseif os(macOS)
                // Use SF Symbols on macOS 11+
                if #available(macOS 11.0, *) {
                    markerView.glyphImage = NSImage(systemSymbolName: "flag.checkered", accessibilityDescription: "End")
                } else {
                    // Fallback for older macOS versions
                    markerView.glyphText = "E"
                }
#endif
            } else if annotation.title == "Peak" {
                markerView.markerTintColor = .orange
#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "arrow.up")
#elseif os(macOS)
                markerView.glyphText = "▲"
#endif
                markerView.displayPriority = .defaultLow // Lower priority to avoid clutter
            } else if annotation.title == "Valley" {
                markerView.markerTintColor = .blue
#if os(iOS)
                markerView.glyphImage = UIImage(systemName: "arrow.down")
#elseif os(macOS)
                markerView.glyphText = "▼"
#endif
                markerView.displayPriority = .defaultLow // Lower priority to avoid clutter
            }
        }
        
        return annotationView
    }
    
#if os(iOS)
// Handle the callout accessory control tap (copy coordinates button)
func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
    print("Copy button tapped in callout")
    guard let annotation = view.annotation else {
        print("No annotation found")
        return
    }
    
    // Format coordinates for clipboard
    let coordinate = annotation.coordinate
    let lat = String(format: "%.6f", coordinate.latitude)
    let lon = String(format: "%.6f", coordinate.longitude)
    let coordinateString = "\(lat), \(lon)"
    
    print("Copying coordinates: \(coordinateString)")
    
    // Copy to clipboard
    UIPasteboard.general.string = coordinateString
    
    // Provide haptic feedback - this is reliable and doesn't require a view controller
    let generator = UINotificationFeedbackGenerator()
    generator.notificationOccurred(.success)
    
    // Try multiple methods to show visual feedback
    print("Attempting to show feedback alert")
    
    // Method 1: Using the superview chain
    if let viewController = view.superview?.findViewController() {
        print("Found view controller via superview chain")
        let alert = UIAlertController(
            title: "Coordinates Copied",
            message: "Location coordinates have been copied to clipboard",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        viewController.present(alert, animated: true)
    }
    // Method 2: Using the window's root view controller
    else if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
            let rootVC = window.rootViewController {
        print("Found root view controller via window")
        let alert = UIAlertController(
            title: "Coordinates Copied",
            message: "Location coordinates have been copied to clipboard",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Handle the case if root view controller is presenting something
        var topVC = rootVC
        while let presentedVC = topVC.presentedViewController {
            topVC = presentedVC
        }
        
        topVC.present(alert, animated: true)
    } else {
        print("Could not find a suitable view controller for showing alert")
        // Just rely on haptic feedback in this case
    }
}
#endif
    
#if os(macOS)
// Handle the click for the copy button on macOS
func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: NSControl) {
    print("Copy button tapped in callout (macOS)")
    guard let annotation = view.annotation else {
        print("No annotation found")
        return
    }
    
    // Format coordinates for clipboard
    let coordinate = annotation.coordinate
    let lat = String(format: "%.6f", coordinate.latitude)
    let lon = String(format: "%.6f", coordinate.longitude)
    let coordinateString = "\(lat), \(lon)"
    
    print("Copying coordinates to macOS pasteboard: \(coordinateString)")
    
    // Copy to clipboard
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(coordinateString, forType: .string)
    
    // Show feedback (could be expanded to use NSPopover or similar)
    print("Successfully copied coordinates to clipboard")
}
#endif
}
