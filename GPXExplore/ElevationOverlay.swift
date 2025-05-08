import SwiftUI
import CoreLocation
import Charts

struct ElevationOverlay: View {
    let trackSegments: [GPXTrackSegment]
    @EnvironmentObject var settings: SettingsModel
    
    // Data structure for chart points
    struct ElevationPoint: Identifiable {
        let distance: Double
        let elevation: Double
        let index: Int
        
        var id: Int { index }
    }
    
    // Get the converted elevation data for display
    private func prepareElevationData() -> (points: [ElevationPoint], min: Double, max: Double, gain: Double) {
        let locations = trackSegments.flatMap { $0.locations }
        let rawElevations = locations.map { $0.altitude }
        
        // Calculate min, max and gain
        let minElevation = rawElevations.min() ?? 0
        let maxElevation = rawElevations.max() ?? 0
        let elevationGain = calculateElevationGain(rawElevations)
        
        // Calculate display elevations with unit conversion if needed
        var chartPoints: [ElevationPoint] = []
        
        // For very large datasets (>2000 points), use stride to sample fewer points
        let strideSize = rawElevations.count > 2000 ? max(1, rawElevations.count / 1000) : 1
        
        for i in stride(from: 0, to: rawElevations.count, by: strideSize) {
            let index = i
            let elevation = rawElevations[index]
            let distanceMeters = calculateDistance(upTo: index, locations: locations)
            
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
                index: index
            ))
        }
        
        // Always include the last point if we're striding
        if strideSize > 1 && !chartPoints.isEmpty && chartPoints.last?.index != rawElevations.count - 1 {
            let index = rawElevations.count - 1
            let elevation = rawElevations[index]
            let distanceMeters = calculateDistance(upTo: index, locations: locations)
            
            let displayDistance = settings.useMetricSystem 
                ? distanceMeters / 1000 
                : distanceMeters / 1609.34
                
            let displayElevation = settings.useMetricSystem
                ? elevation
                : elevation * 3.28084
                
            chartPoints.append(ElevationPoint(
                distance: displayDistance,
                elevation: displayElevation,
                index: index
            ))
        }
        
        return (points: chartPoints, min: minElevation, max: maxElevation, gain: elevationGain)
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
                    
                    // Create a simple chart with area and line
                    ElevationChartView(
                        points: elevationData.points,
                        minValue: elevationData.min * (settings.useMetricSystem ? 1.0 : 3.28084),
                        maxValue: elevationData.max * (settings.useMetricSystem ? 1.0 : 3.28084),
                        yUnit: yUnit,
                        xUnit: xUnit
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
}

// Extract chart into a separate view component to reduce complexity
struct ElevationChartView: View {
    let points: [ElevationOverlay.ElevationPoint]
    let minValue: Double
    let maxValue: Double
    let yUnit: String
    let xUnit: String
    
    var body: some View {
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
        }
        .chartYScale(domain: [minValue * 0.95, maxValue * 1.05])
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
    }
}
