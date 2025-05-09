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

                    // Zoom indicator and reset button
                    if zoomRange != nil {
                        HStack(spacing: 6) {
                            // Zoom status indicator
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)

                                let zoomStart = String(format: "%.1f", zoomRange?.lowerBound ?? 0)
                                let zoomEnd = String(format: "%.1f", zoomRange?.upperBound ?? 0)
                                let unit = settings.useMetricSystem ? "km" : "mi"

                                Text("\(zoomStart)-\(zoomEnd)\(unit)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.1))
                            )

                            // Zoom out button
                            Button(action: {
                                // Reset zoom range to nil
                                zoomRange = nil
                            }) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12))
                                    .padding(5)
                                    .background(Color.secondary.opacity(0.2))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: zoomRange != nil)
                        .help("Reset zoom")
                    }
                }
                
                // Elevation chart using Swift Charts
                if !elevationData.points.isEmpty {
                    // Define common values
                    let yUnit = settings.useMetricSystem ? "m" : "ft"
                    let xUnit = settings.useMetricSystem ? "km" : "mi"
                    
                    // Create chart with interactions
                    OptimizedElevationChartView(
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
struct OptimizedElevationChartView: View {
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
    @State private var isProcessingHover: Bool = false
    @State private var pendingHoverLocation: CGPoint? = nil
    @State private var indexCache: [CGFloat: Int] = [:] // Cache to store x position to index mapping
    let hoverThrottleInterval: TimeInterval = 0.02 // 20ms for better responsiveness
    @State private var pointsArray: [Int: Int] = [:] // Cache for quick point lookups
    
    // Efficient helper function for hover processing with enhanced consistency
    private func processHoverLocation(_ location: CGPoint, completion: @escaping (Int?) -> Void) {
        // Use coarser cache key (5px precision) to ensure consistent point selection
        // within small mouse movements
        let roundedX = floor(location.x / 5) * 5

        // Fast path: check cache first - if we already processed a nearby position, use cached result
        if let cachedIndex = indexCache[roundedX] {
            completion(cachedIndex)
            return
        }

        // Background processing for better UI responsiveness
        DispatchQueue.global(qos: .userInteractive).async {
            guard !self.points.isEmpty, self.chartBounds.width > 0 else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Get min and max distances from points
            let defaultMinDistance = self.points.first?.distance ?? 0
            let defaultMaxDistance = self.points.last?.distance ?? 0

            // Get the actual visible distances based on zoom range
            let minDistance = self.zoomRange?.lowerBound ?? defaultMinDistance
            let maxDistance = self.zoomRange?.upperBound ?? defaultMaxDistance

            // Convert x position to distance, respecting the current zoom level
            let relativeX = (location.x - self.chartBounds.minX) / self.chartBounds.width
            let distance = minDistance + relativeX * (maxDistance - minDistance)

            // Avoid finding points by using direct positional mapping for large datasets
            // This creates more consistent hover behavior (equal x-spacing between hover points)
            if self.points.count > 100 && self.zoomRange == nil {
                // Use direct index calculation only when not zoomed
                let pointCount = self.points.count
                let scaledIndex = min(pointCount - 1, max(0, Int(relativeX * Double(pointCount))))

                let result = self.points[scaledIndex].index
                DispatchQueue.main.async {
                    // Update cache on main thread
                    self.indexCache[roundedX] = result
                    completion(result)
                }
                return
            }

            // For smaller datasets or when zoomed, use exact distance calculation
            var closestIndex = 0
            var closestDistance = Double.greatestFiniteMagnitude

            for (i, point) in self.points.enumerated() {
                let currentDistance = abs(point.distance - distance)
                if currentDistance < closestDistance {
                    closestDistance = currentDistance
                    closestIndex = i
                }
            }

            // Cache and return result
            let result = self.points[closestIndex].index
            DispatchQueue.main.async {
                // Update cache with a range of nearby x values for stability
                for i in -2...2 {
                    self.indexCache[roundedX + CGFloat(i*5)] = result
                }
                completion(result)
            }
        }
    }
    
    // Direction tracking for consistent hover movement
    @State private var lastDirection: CGFloat = 0
    @State private var directionChangeCount: Int = 0
    @State private var lastPointIndex: Int? = nil

    // Helper method for handling hover events that supports background processing
    // with direction consistency to prevent back-and-forth jitter
    private func handleHover(at location: CGPoint) {
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastHoverProcessTime)

        // If we're already processing a hover, store this as pending for later
        if isProcessingHover {
            pendingHoverLocation = location
            return
        }

        // Process if sufficient time has passed
        if timeSinceLastUpdate >= hoverThrottleInterval {
            // Calculate direction of movement
            var currentDirection: CGFloat = 0
            var locationToUse = location

            if lastHoverLocation != .zero {
                let dx = location.x - lastHoverLocation.x
                currentDirection = dx

                // Check for direction changes - avoid applying prediction if direction is inconsistent
                // to prevent oscillation between points
                if lastDirection * currentDirection < 0 {
                    // Direction changed, increment counter
                    directionChangeCount += 1
                } else if abs(dx) > 3 {
                    // Moving consistently in one direction at reasonable speed, reset counter
                    directionChangeCount = 0
                }

                // Only apply predictive offset if we haven't had many direction changes recently
                // and we're moving at a reasonable speed
                if directionChangeCount < 2 && abs(dx) > 1 {
                    // Use more conservative predictive offset to avoid oscillation
                    let predictOffset = min(8.0, max(-8.0, dx * 1.5))
                    locationToUse = CGPoint(x: location.x + predictOffset, y: location.y)
                }

                // Update last direction
                if abs(dx) > 1 {
                    lastDirection = currentDirection
                }
            }

            // Set processing flag to avoid concurrent processing
            isProcessingHover = true

            // Use background processing
            processHoverLocation(locationToUse) { index in
                if let index = index {
                    // Prevent oscillation by enforcing consistent direction of point changes
                    let shouldUpdate = self.selectedPointIndex == nil ||
                                      self.lastPointIndex == nil ||
                                      (self.lastDirection > 0 && index > self.lastPointIndex!) ||
                                      (self.lastDirection < 0 && index < self.lastPointIndex!) ||
                                      self.directionChangeCount >= 3 // Allow changes if we can't detect clear direction

                    if shouldUpdate && self.selectedPointIndex != index {
                        self.selectedPointIndex = index
                        self.lastPointIndex = index
                        self.onHover?(index)
                    }
                }

                // Update tracking variables
                self.lastHoverProcessTime = now
                self.lastHoverLocation = location
                self.isProcessingHover = false

                // Process any pending hover that came in while processing
                if let pendingLocation = self.pendingHoverLocation {
                    self.pendingHoverLocation = nil
                    // Process the pending location on the next run loop
                    DispatchQueue.main.async {
                        self.handleHover(at: pendingLocation)
                    }
                }
            }
        }
    }
    
    // Legacy function for backward compatibility - fallback only
    private func chartPositionFromGesture(_ location: CGPoint) -> (distance: Double, index: Int)? {
        guard !points.isEmpty, chartBounds.width > 0 else { return nil }

        // Get min and max distances from points
        let defaultMinDistance = points.first?.distance ?? 0
        let defaultMaxDistance = points.last?.distance ?? 0

        // Use zoom range if available
        let minDistance = zoomRange?.lowerBound ?? defaultMinDistance
        let maxDistance = zoomRange?.upperBound ?? defaultMaxDistance

        // Convert x position to distance, respecting the current zoom level
        let relativeX = (location.x - chartBounds.minX) / chartBounds.width
        let distance = minDistance + relativeX * (maxDistance - minDistance)

        // First check cache
        let roundedX = round(location.x)
        if let cachedIndex = indexCache[roundedX] {
            return (distance, cachedIndex)
        }

        // When zoomed, we need to find the nearest point by distance
        if zoomRange != nil {
            var closestIndex = 0
            var closestDiff = Double.greatestFiniteMagnitude

            for (i, point) in points.enumerated() {
                let diff = abs(point.distance - distance)
                if diff < closestDiff {
                    closestDiff = diff
                    closestIndex = i
                }
            }

            return (distance, points[closestIndex].index)
        }

        // Fallback to simple predicted index if not zoomed
        let pointCount = points.count
        let predictedIndex = Int(relativeX * Double(pointCount - 1))
        let safeIndex = max(0, min(predictedIndex, pointCount - 1))

        return (distance, points[safeIndex].index)
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
        // Clear cache when zoom changes
        let _ = zoomRange.map { _ in
            // This will run whenever zoomRange changes
            DispatchQueue.main.async {
                indexCache = [:]
                selectedPointIndex = nil
            }
        }

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
                            // Build an index for fast point lookups
                            for (i, point) in points.enumerated() {
                                pointsArray[point.index] = i
                            }
                        }
                        .onChange(of: bounds) { newBounds in
                            chartBounds = newBounds
                            // Clear cache when bounds change
                            indexCache = [:]
                        }

                    // Overlay for gesture handling
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        #if os(iOS) || os(visionOS)
                        // iOS/iPadOS hover using drag gesture with location and background processing
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging && (dragStart == nil || abs(value.location.x - dragStart!) < 3) {
                                        // Process hover event in background with optimizations
                                        handleHover(at: value.location)

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
                                lastHoverLocation = .zero
                            }
                        }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if !isDragging {
                                    // Process hover event in background with optimizations
                                    handleHover(at: location)
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

            // Floating zoom out button overlay in the chart
            if zoomRange != nil {
                VStack {
                    HStack {
                        // Zoomed view indicator
                        Text("Zoomed view")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 12)
                            .padding(.top, 8)

                        Spacer()

                        Button(action: {
                            // Reset zoom range to nil
                            onDragSelection?(0, 0)
                        }) {
                            HStack(spacing: 4) {
                                Text("Reset")
                                    .font(.caption)
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.primary)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.15))
                                    .shadow(radius: 1)
                            )
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .padding([.top, .trailing], 8)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.2), value: zoomRange != nil)
                        .help("Reset zoom")
                        .zIndex(100) // Ensure button is above the chart
                    }

                    Spacer()
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
