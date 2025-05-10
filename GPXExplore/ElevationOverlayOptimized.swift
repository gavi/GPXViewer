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

    // State for chart selection and interaction
    @State private var selectedDistance: Double? = nil
    @State private var isDragging: Bool = false
    @State private var dragStart: Double? = nil
    @State private var dragEnd: Double? = nil

    // Get y scale domain
    private var yScaleDomain: ClosedRange<Double> {
        (minValue * 0.95)...(maxValue * 1.05)
    }

    // Performance optimization state
    @State private var lastHoverTime: Date = Date.distantPast
    @State private var throttleInterval: TimeInterval = 0.05 // 50ms throttle
    @State private var lastHoverLocation: CGPoint = .zero

    // Find point at a chart position using ChartProxy (directly gets the index)
    private func findPointAt(position: CGPoint, proxy: ChartProxy) -> (point: ElevationOverlay.ElevationPoint, index: Int)? {
        // Throttle hover events for large datasets
        let now = Date()
        if points.count > 1000 && // Only throttle for large datasets
           now.timeIntervalSince(lastHoverTime) < throttleInterval &&
           abs(position.x - lastHoverLocation.x) < 5.0 {
            // Skip processing if we just processed a nearby point recently
            return nil
        }

        // Update hover tracking
        lastHoverTime = now
        lastHoverLocation = position

        // Convert x-position to distance value using ChartProxy
        guard let distance = proxy.value(atX: position.x, as: Double.self),
              !points.isEmpty else { return nil }

        // Fast approximation for very large datasets (10000+ points)
        if points.count > 5000 && !isDragging {
            // O(1) direct index calculation for extremely large datasets
            let totalDistance = points.last!.distance - points.first!.distance
            let normalizedPosition = min(1.0, max(0.0,
                                           (distance - points.first!.distance) / totalDistance))
            let index = min(points.count - 1, max(0, Int(normalizedPosition * Double(points.count - 1))))
            return (points[index], points[index].index)
        }

        // Binary search to find the closest point to this distance
        // This is much more efficient than linear search for large datasets

        // Handle edge cases
        if points.count <= 1 {
            return points.isEmpty ? nil : (points[0], points[0].index)
        }

        if distance <= points.first!.distance {
            return (points.first!, points.first!.index)
        }

        if distance >= points.last!.distance {
            return (points.last!, points.last!.index)
        }

        // Binary search for the two points that bracket this distance
        var low = 0
        var high = points.count - 1

        while high - low > 1 {
            let mid = (low + high) / 2
            if points[mid].distance < distance {
                low = mid
            } else {
                high = mid
            }
        }

        // Determine which of the two bracketing points is closer
        let distLow = abs(points[low].distance - distance)
        let distHigh = abs(points[high].distance - distance)

        return distLow < distHigh
            ? (points[low], points[low].index)
            : (points[high], points[high].index)
    }

    var body: some View {
        Chart {
            // Area under the line
            ForEach(points) { point in
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

            // The elevation line
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

            // Highlight selected point with a marker
            if let distance = selectedDistance {
                // Find the point for the UI - already optimized since we're only doing this for display
                if let selectedPoint = points.first(where: {
                    // Use approximate equality to handle small floating point differences
                    abs($0.distance - distance) < 0.00001
                }) ?? points.first(where: { $0.distance > distance }) {

                    // Selection indicator rule
                    RuleMark(
                        x: .value("Selected", selectedPoint.distance)
                    )
                    .foregroundStyle(Color.gray.opacity(0.3))
                    .zIndex(-1)

                    // Show point marker
                    PointMark(
                        x: .value("Distance", selectedPoint.distance),
                        y: .value("Elevation", selectedPoint.elevation)
                    )
                    .foregroundStyle(Color.white)
                    .symbolSize(150)

                    PointMark(
                        x: .value("Distance", selectedPoint.distance),
                        y: .value("Elevation", selectedPoint.elevation)
                    )
                    .foregroundStyle(Color.red)
                    .symbolSize(100)
                }
            }

            // Show drag selection area
            if isDragging, let start = dragStart, let end = dragEnd {
                RectangleMark(
                    xStart: .value("Start", min(start, end)),
                    xEnd: .value("End", max(start, end)),
                    yStart: .value("Bottom", minValue * 0.95),
                    yEnd: .value("Top", maxValue * 1.05)
                )
                .foregroundStyle(Color.blue.opacity(0.2))
            }
        }
        .chartYScale(domain: yScaleDomain)
        .chartXScale(domain: zoomRange ?? (points.first?.distance ?? 0)...(points.last?.distance ?? 1))
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
        // Use chart overlay for more precise hover control
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    #if os(iOS) || os(visionOS)
                    // iOS - Only use tap/hover with no drag zoom at all
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Always use for hover only - no zoom
                                selectedDistance = nil

                                // Use drag location for hover effect
                                if let (point, index) = findPointAt(position: value.location, proxy: proxy) {
                                    // Update UI with point position
                                    selectedDistance = point.distance
                                    // Report the point's index directly to parent
                                    onHover?(index)
                                }
                            }
                            .onEnded { _ in
                                // Clear selection when drag ends
                                selectedDistance = nil
                                onHover?(nil)
                            }
                    )
                    #elseif os(macOS)
                    // macOS hover handling
                    .onHover { hovering in
                        if !hovering && !isDragging {
                            selectedDistance = nil
                            onHover?(nil)
                        }
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if !isDragging {
                                // Use our optimized point finding with index
                                if let (point, index) = findPointAt(position: location, proxy: proxy) {
                                    // Update UI with point position
                                    selectedDistance = point.distance
                                    // Report the point's index directly to parent
                                    onHover?(index)
                                }
                            }
                        case .ended:
                            if !isDragging {
                                selectedDistance = nil
                                onHover?(nil)
                            }
                        }
                    }
                    // Add combined drag gesture for direct selection
                    .gesture(
                        DragGesture(minimumDistance: 3) // Small threshold for macOS
                            .onChanged { value in
                                // Start dragging immediately - macOS has better hover separation
                                if !isDragging {
                                    isDragging = true
                                    dragStart = proxy.value(atX: value.startLocation.x, as: Double.self)
                                }

                                // Update end position
                                dragEnd = proxy.value(atX: value.location.x, as: Double.self)
                            }
                            .onEnded { _ in
                                if let start = dragStart, let end = dragEnd, isDragging {
                                    // Only trigger zoom if selection has meaningful width
                                    if abs(end - start) > 0.05 {
                                        onDragSelection?(
                                            min(start, end),
                                            max(start, end)
                                        )
                                    }
                                }

                                // Reset state
                                isDragging = false
                                dragStart = nil
                                dragEnd = nil
                            }
                    )
                    #endif
            }
        }
        // Double tap/click gesture is sufficient since we integrated drag into the overlay
        // Double tap/click to reset zoom (works on both platforms)
        .gesture(
            TapGesture(count: 2)
                .onEnded {
                    // Double tap resets zoom
                    onDragSelection?(0, 0)
                }
        )
    }
}
