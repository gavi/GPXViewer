import SwiftUI
import CoreLocation
import HealthKit

struct RouteInfoOverlay: View {
    let trackSegments: [GPXTrackSegment]
    let workout: HKWorkout
    @EnvironmentObject var settings: SettingsModel
    
    // Get track name from workout metadata
    private var trackName: String {
        return workout.metadata?["name"] as? String ?? "Unnamed Track"
    }
    
    var body: some View {
        VStack {
            // Floating workout info section with transparency
            VStack(alignment: .leading, spacing: 8) {
//                // Track name as headline
//                Text(trackName)
//                    .font(.headline)
//                    .lineLimit(1)
                
                // Calculate total points across all segments
                let totalPoints = trackSegments.reduce(0) { $0 + $1.locations.count }
                let segmentCount = trackSegments.count
                
                Text("\(totalPoints) data points in \(segmentCount) segment\(segmentCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Started: \(workout.startDate, style: .date) \(workout.startDate, style: .time)")
                            .font(.subheadline)
                        
                        Text("Ended: \(workout.endDate, style: .date) \(workout.endDate, style: .time)")
                            .font(.subheadline)
                    }
                    
                    Spacer()
                    
                    if let distance = workout.totalDistance?.doubleValue(for: .meter()) {
                        Text(settings.formatDistance(distance))
                            .font(.headline)
                    }
                }
                
                // Add elevation data
                if !trackSegments.isEmpty {
                    Divider()
                    
                    // Combine all locations to calculate overall elevation stats
                    let allLocations = trackSegments.flatMap { $0.locations }
                    let elevations = allLocations.map { $0.altitude }
                    
                    if let minElevation = elevations.min(), 
                       let maxElevation = elevations.max() {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Elevation")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text("Min: \(formatElevation(minElevation))")
                                    .font(.caption)
                                
                                Text("Max: \(formatElevation(maxElevation))")
                                    .font(.caption)
                                
                                Text("Gain: \(formatElevation(calculateElevationGain(elevations)))")
                                    .font(.caption)
                            }
                            
                            Spacer()
                            
                            // Elevation color legend
                            HStack(spacing: 8) {
                                // Gradient color bar
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 0, green: 0.3, blue: 1.0),  // Low - Blue
                                        Color(red: 0, green: 1.0, blue: 0.0),  // Medium - Green
                                        Color(red: 1.0, green: 0.2, blue: 0.0)   // High - Red
                                    ]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                                .frame(width: 8, height: 40)
                                .cornerRadius(3)
                                
                                // Labels next to the gradient
                                VStack(alignment: .leading) {
                                    Text("High")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("Low")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            .frame(height: 44)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            #if os(iOS)
                            .background(Color(UIColor.systemBackground).opacity(0.7))
                            #elseif os(macOS)
                            .background(Color(NSColor.windowBackgroundColor).opacity(0.7))
                            #endif
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .padding()
            #if os(iOS)
            .background(Color(UIColor.systemBackground).opacity(0.8))
            #elseif os(macOS)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            #endif
            .cornerRadius(12)
            .padding([.horizontal, .top])
            
            Spacer()
        }
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
}
