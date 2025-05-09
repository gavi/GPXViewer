import SwiftUI
import CoreLocation
import Charts

struct ElevationOverlay: View {
    let trackSegments: [GPXTrackSegment]
    @EnvironmentObject var settings: SettingsModel

    // Binding to report the currently hovered point for map marker
    @Binding var selectedPointIndex: Int?
    @Binding var zoomRange: ClosedRange<Double>?

    // Default initializer with optional binding for hover point
    init(trackSegments: [GPXTrackSegment], selectedPointIndex: Binding<Int?> = .constant(nil), zoomRange: Binding<ClosedRange<Double>?> = .constant(nil)) {
        self.trackSegments = trackSegments
        self._selectedPointIndex = selectedPointIndex
        self._zoomRange = zoomRange
    }

    // Data structure for chart points
    struct ElevationPoint: Identifiable {
        let distance: Double
        let elevation: Double
        let index: Int
        let originalIndex: Int // Original index in the locations array

        var id: Int { index }
    }

    // Get the converted elevation data for display
    private func prepareElevationData() -> (points: [ElevationPoint], min: Double, max: Double, gain: Double, locations: [CLLocation]) {
        let locations = trackSegments.flatMap { $0.locations }
        let rawElevations = locations.map { $0.altitude }

        // Calculate min, max and gain
        let minElevation = rawElevations.min() ?? 0
        let maxElevation = rawElevations.max() ?? 0
        let elevationGain = calculateElevationGain(rawElevations)

        // Calculate display elevations with unit conversion if needed
        var chartPoints: [ElevationPoint] = []

        // Use the chart data density setting to determine stride size
        let strideSize = calculateStrideSize(for: rawElevations.count)

        for (i, originalIndex) in stride(from: 0, to: rawElevations.count, by: strideSize).enumerated() {
            let elevation = rawElevations[originalIndex]
            let distanceMeters = calculateDistance(upTo: originalIndex, locations: locations)

            // Convert to proper units (kilometers or miles)
            let displayDistance = settings.useMetricSystem
                ? distanceMeters / 1000  // to kilometers
                : distanceMeters / 1609.34  // to miles

            // Convert elevation if needed
            let displayElevation = settings.useMetricSystem
                ? elevation  // keep as meters
                : elevation * 3.28084  // to feet

            chartPoints.append(ElevationPoint(
                distance: displayDistance,
                elevation: displayElevation,
                index: i,
                originalIndex: originalIndex
            ))
        }

        // Always include the last point if we're striding
        if strideSize > 1 && !chartPoints.isEmpty && chartPoints.last?.originalIndex != rawElevations.count - 1 {
            let originalIndex = rawElevations.count - 1
            let elevation = rawElevations[originalIndex]
            let distanceMeters = calculateDistance(upTo: originalIndex, locations: locations)

            let displayDistance = settings.useMetricSystem
                ? distanceMeters / 1000
                : distanceMeters / 1609.34

            let displayElevation = settings.useMetricSystem
                ? elevation
                : elevation * 3.28084

            chartPoints.append(ElevationPoint(
                distance: displayDistance,
                elevation: displayElevation,
                index: chartPoints.count,
                originalIndex: originalIndex
            ))
        }

        return (points: chartPoints, min: minElevation, max: maxElevation, gain: elevationGain, locations: locations)
    }

    // Calculate cumulative distance up to a specific index
    private func calculateDistance(upTo index: Int, locations: [CLLocation]) -> Double {
        guard index > 0 && index < locations.count else { return 0 }

        var totalDistance: Double = 0
        for i in 1...index {
            totalDistance += locations[i-1].distance(from: locations[i])
        }

        return totalDistance
    }

    var body: some View {
        VStack {
            // Get all elevation data first to simplify view code
            let elevationData = prepareElevationData()

            // Elevation chart with metrics
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Elevation Profile")
                            .font(.headline)

                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .foregroundColor(.blue)
                                Text("Min: \(formatElevation(elevationData.min))")
                                    .font(.caption)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .foregroundColor(.red)
                                Text("Max: \(formatElevation(elevationData.max))")
                                    .font(.caption)
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "mountain.2")
                                    .foregroundColor(.green)
                                Text("Gain: \(formatElevation(elevationData.gain))")
                                    .font(.caption)
                            }
                        }
                    }

                    Spacer()
                }

                // Elevation chart using Swift Charts
                if !elevationData.points.isEmpty {
                    // Define common values
                    let yUnit = settings.useMetricSystem ? "m" : "ft"
                    let xUnit = settings.useMetricSystem ? "km" : "mi"

                    // Create chart with interactions
                    ElevationChartView(
                        points: elevationData.points,
                        minValue: elevationData.min * (settings.useMetricSystem ? 1.0 : 3.28084),
                        maxValue: elevationData.max * (settings.useMetricSystem ? 1.0 : 3.28084),
                        yUnit: yUnit,
                        xUnit: xUnit,
                        onHover: { pointIndex in
                            // Throttle hover updates to prevent excessive map marker updates
                            // Only update if we have a point and it's different from current selection
                            if let point = elevationData.points.first(where: { $0.index == pointIndex }) {
                                // Only update if index actually changed to reduce map updates
                                if self.selectedPointIndex != point.originalIndex {
                                    self.selectedPointIndex = point.originalIndex
                                }
                            } else {
                                self.selectedPointIndex = nil
                            }
                        },
                        onDragSelection: { startDistance, endDistance in
                            if startDistance != endDistance {
                                zoomRange = startDistance...endDistance
                            } else {
                                zoomRange = nil
                            }
                        },
                        zoomRange: zoomRange
                    )
                    .frame(height: 120)
                    .padding(.vertical, 4)
                }
            }
            .padding()
            #if os(iOS) || os(visionOS)
            .background(Color(UIColor.systemBackground).opacity(0.8))
            #elseif os(macOS)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            #endif
            .cornerRadius(12)
            .padding([.horizontal, .bottom])
        }
    }
    
    // Helper function to calculate elevation gain from a series of elevation points
    private func calculateElevationGain(_ elevations: [Double]) -> Double {
        guard elevations.count > 1 else { return 0 }
        
        var gain: Double = 0
        
        for i in 1..<elevations.count {
            let diff = elevations[i] - elevations[i-1]
            // Only count positive elevation changes (uphill)
            if diff > 0 {
                gain += diff
            }
        }
        
        return gain
    }
    
    // Helper function to format elevation
    private func formatElevation(_ elevation: Double) -> String {
        if settings.useMetricSystem {
            return String(format: "%.0f m", elevation)
        } else {
            let feet = elevation * 3.28084
            return String(format: "%.0f ft", feet)
        }
    }
    
    // Helper function to calculate appropriate stride size based on settings
    private func calculateStrideSize(for dataPointCount: Int) -> Int {
        // Get the stride factor from settings
        let strideFactor = settings.chartDataStride
        
        // For small datasets, don't stride at all
        if dataPointCount <= 500 {
            return 1
        }
        
        // For medium datasets, use moderate stride if density is not maximum
        if dataPointCount <= 2000 {
            return settings.chartDataDensity >= 1.0 ? 1 : strideFactor
        }
        
        // For very large datasets, calculate a dynamic stride to get a reasonable number of points
        // Min points: dataPointCount / (strideFactor * 10)
        // Max points: dataPointCount / strideFactor
        let baseStride = max(1, dataPointCount / 2000) * strideFactor
        return baseStride
    }
}

// Extract chart into a separate view component to reduce complexity
struct ElevationChartView: View {
    let points: [ElevationOverlay.ElevationPoint]
    let minValue: Double
    let maxValue: Double
    let yUnit: String
    let xUnit: String
    var onHover: ((Int?) -> Void)? = nil
    var onDragSelection: ((Double, Double) -> Void)? = nil
    var zoomRange: ClosedRange<Double>? = nil

    // State for gesture handling
    @State private var selectedPointIndex: Int? = nil
    @State private var isDragging: Bool = false
    @State private var dragStart: CGFloat? = nil
    @State private var dragEnd: CGFloat? = nil
    @State private var chartBounds: CGRect = .zero

    // State for optimizing hover performance
    @State private var lastHoverProcessTime: Date = Date.distantPast
    @State private var lastHoverLocation: CGPoint = .zero
    let hoverThrottleInterval: TimeInterval = 0.05 // 50ms is more responsive than 250ms

    // Helper function to convert gesture location to chart position with optimized point finding
    private func chartPositionFromGesture(_ location: CGPoint) -> (distance: Double, index: Int)? {
        guard !points.isEmpty, chartBounds.width > 0 else { return nil }

        // Get min and max distances from points
        let minDistance = points.first?.distance ?? 0
        let maxDistance = points.last?.distance ?? 0

        // Convert x position to distance
        let relativeX = (location.x - chartBounds.minX) / chartBounds.width
        let distance = minDistance + relativeX * (maxDistance - minDistance)

        // Use a more efficient algorithm to find the closest point
        // First, calculate a predicted index based on the relative position
        let pointCount = points.count
        let predictedIndex = Int(relativeX * Double(pointCount - 1))

        // Clamp the index to valid range
        let safeIndex = max(0, min(predictedIndex, pointCount - 1))

        // Start from the predicted index and search linearly in both directions
        // This is much faster than searching the entire array
        let centralPoint = points[safeIndex]
        var bestDistance = abs(centralPoint.distance - distance)
        var bestIndex = safeIndex

        // Check up to 5 points in each direction from the predicted position
        let searchRange = 5
        let startSearch = max(0, safeIndex - searchRange)
        let endSearch = min(pointCount - 1, safeIndex + searchRange)

        for i in startSearch...endSearch {
            let point = points[i]
            let pointDistance = abs(point.distance - distance)

            if pointDistance < bestDistance {
                bestDistance = pointDistance
                bestIndex = i
            }
        }

        return (distance, points[bestIndex].index)
    }

    // Get domain for charts based on zoom
    private var chartDomain: ClosedRange<Double>? {
        if let zoomRange = zoomRange {
            return zoomRange
        }
        return nil
    }

    // Get y scale domain
    private var yScaleDomain: ClosedRange<Double> {
        (minValue * 0.95)...(maxValue * 1.05)
    }

    var body: some View {
        ZStack {
            // Base chart
            Chart {
                // Use ForEach with individual points for Swift Charts compatibility
                ForEach(points) { point in
                    // Area under the line
                    AreaMark(
                        x: .value("Distance", point.distance),
                        y: .value("Elevation", point.elevation)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.green.opacity(0.3),
                                Color.red.opacity(0.3)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                }

                // Use ForEach for line too to avoid compiler complexity
                ForEach(points) { point in
                    LineMark(
                        x: .value("Distance", point.distance),
                        y: .value("Elevation", point.elevation)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.green, Color.red],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // Highlight selected point with a marker if available
                if let selectedIndex = selectedPointIndex, let point = points.first(where: { $0.index == selectedIndex }) {
                    PointMark(
                        x: .value("Distance", point.distance),
                        y: .value("Elevation", point.elevation)
                    )
                    .foregroundStyle(Color.white)
                    .symbolSize(150)

                    PointMark(
                        x: .value("Distance", point.distance),
                        y: .value("Elevation", point.elevation)
                    )
                    .foregroundStyle(Color.red)
                    .symbolSize(100)
                }

                // Show drag selection area
                if isDragging, let start = dragStart, let end = dragEnd,
                   let (startDistance, _) = chartPositionFromGesture(CGPoint(x: start, y: 0)),
                   let (endDistance, _) = chartPositionFromGesture(CGPoint(x: end, y: 0)) {

                    RectangleMark(
                        xStart: .value("Start", min(startDistance, endDistance)),
                        xEnd: .value("End", max(startDistance, endDistance)),
                        yStart: .value("Bottom", minValue * 0.95),
                        yEnd: .value("Top", maxValue * 1.05)
                    )
                    .foregroundStyle(Color.blue.opacity(0.2))
                }
            }
            .chartYScale(domain: yScaleDomain)
            .chartXScale(domain: chartDomain ?? (points.first?.distance ?? 0)...(points.last?.distance ?? 1))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let yValue = value.as(Double.self) {
                            Text("\(Int(yValue)) \(yUnit)")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let xValue = value.as(Double.self) {
                            Text(String(format: "%.1f \(xUnit)", xValue))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    // Save chart bounds for coordinate conversion
                    let bounds = geometry.frame(in: .local)
                    Color.clear
                        .onAppear {
                            chartBounds = bounds
                        }
                        .onChange(of: bounds) { newBounds in
                            chartBounds = newBounds
                        }

                    // Overlay for gesture handling
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        #if os(iOS) || os(visionOS)
                        // iOS/iPadOS hover using drag gesture with location
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // Apply throttling and predictive behavior for smoother hover response
                                    let now = Date()
                                    let timeSinceLastUpdate = now.timeIntervalSince(lastHoverProcessTime)

                                    // Store location for velocity calculation
                                    let currentLocation = value.location

                                    if !isDragging && (dragStart == nil || abs(value.location.x - dragStart!) < 3) {
                                        // Single tap or small movement - handle as hover
                                        // Process if sufficient time has passed or it's a significant movement
                                        if timeSinceLastUpdate >= hoverThrottleInterval {
                                            // Add predictive behavior - calculate velocity and predict location
                                            var locationToUse = currentLocation

                                            // Calculate movement direction and apply a small prediction factor
                                            // to "look ahead" where the mouse is moving
                                            if lastHoverLocation != .zero {
                                                let dx = currentLocation.x - lastHoverLocation.x
                                                let predictiveOffset = min(8.0, max(-8.0, dx * 2.0)) // limit predictive offset
                                                locationToUse = CGPoint(x: currentLocation.x + predictiveOffset, y: currentLocation.y)
                                            }

                                            // Find nearest point to the predicted location
                                            if let (_, index) = chartPositionFromGesture(locationToUse) {
                                                // Only update if the index changed
                                                if selectedPointIndex != index {
                                                    selectedPointIndex = index
                                                    onHover?(index)
                                                }
                                            }

                                            // Update tracking variables
                                            lastHoverProcessTime = now
                                            lastHoverLocation = currentLocation
                                        }

                                        // Start drag if we've moved more than initial touch
                                        if dragStart == nil {
                                            dragStart = value.location.x
                                        }
                                    } else {
                                        // We're in drag mode for zoom selection
                                        isDragging = true
                                        dragEnd = value.location.x
                                    }
                                }
                                .onEnded { value in
                                    // Handle end of gesture
                                    if isDragging, let start = dragStart, let end = dragEnd,
                                       let (startDistance, _) = chartPositionFromGesture(CGPoint(x: start, y: 0)),
                                       let (endDistance, _) = chartPositionFromGesture(CGPoint(x: end, y: 0)) {

                                        // Only trigger zoom if selection has meaningful width
                                        if abs(end - start) > 10 {
                                            onDragSelection?(
                                                min(startDistance, endDistance),
                                                max(startDistance, endDistance)
                                            )
                                        }
                                    }

                                    // Reset drag state
                                    isDragging = false
                                    dragStart = nil
                                    dragEnd = nil
                                }
                        )
                        // Additional tap gesture to reset zoom
                        .gesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    // Double tap resets zoom
                                    onDragSelection?(0, 0)
                                }
                        )
                        #elseif os(macOS)
                        // macOS hover uses onHover
                        .onHover { hovering in
                            if !hovering {
                                selectedPointIndex = nil
                                onHover?(nil)
                            }
                        }
                        .onContinuousHover { phase in
                            // Apply predictive and throttled behavior for smoother hover
                            let now = Date()
                            let timeSinceLastUpdate = now.timeIntervalSince(lastHoverProcessTime)

                            switch phase {
                            case .active(let location):
                                if !isDragging && timeSinceLastUpdate >= hoverThrottleInterval {
                                    // Add predictive behavior - calculate velocity and predict location
                                    var locationToUse = location

                                    // Calculate movement direction and apply a small prediction factor
                                    // to "look ahead" where the mouse is moving
                                    if lastHoverLocation != .zero {
                                        let dx = location.x - lastHoverLocation.x
                                        let predictiveOffset = min(8.0, max(-8.0, dx * 2.0)) // limit predictive offset
                                        locationToUse = CGPoint(x: location.x + predictiveOffset, y: location.y)
                                    }

                                    // Find nearest point to the predicted location
                                    if let (_, index) = chartPositionFromGesture(locationToUse) {
                                        // Only update if the index changed
                                        if selectedPointIndex != index {
                                            selectedPointIndex = index
                                            onHover?(index)
                                        }
                                    }

                                    // Update tracking variables
                                    lastHoverProcessTime = now
                                    lastHoverLocation = location
                                }
                            case .ended:
                                if !isDragging {
                                    selectedPointIndex = nil
                                    onHover?(nil)
                                    lastHoverLocation = .zero
                                }
                            }
                        }
                        // Drag gesture for selection
                        .gesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { value in
                                    isDragging = true
                                    if dragStart == nil {
                                        dragStart = value.startLocation.x
                                    }
                                    dragEnd = value.location.x
                                }
                                .onEnded { value in
                                    if let start = dragStart, let end = dragEnd,
                                       let (startDistance, _) = chartPositionFromGesture(CGPoint(x: start, y: 0)),
                                       let (endDistance, _) = chartPositionFromGesture(CGPoint(x: end, y: 0)) {

                                        onDragSelection?(
                                            min(startDistance, endDistance),
                                            max(startDistance, endDistance)
                                        )
                                    }

                                    isDragging = false
                                    dragStart = nil
                                    dragEnd = nil
                                }
                        )
                        // Double click to reset zoom
                        .gesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    // Double click resets zoom
                                    onDragSelection?(0, 0)
                                }
                        )
                        #endif
                }
            }
        }
        .gesture(
            MagnificationGesture()
                .onEnded { value in
                    // Reset zoom on pinch out (value > 1)
                    if value > 1.2 {
                        onDragSelection?(0, 0)
                    }
                }
        )
    }
}
