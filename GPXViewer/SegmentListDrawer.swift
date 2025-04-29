import SwiftUI
import MapKit
import CoreLocation

#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
typealias PlatformColor = NSColor
#endif

struct SegmentListDrawer: View {
    @Binding var segments: [GPXTrackSegment]
    @Binding var visibleSegments: [Bool]
    @Binding var isDrawerOpen: Bool
    @EnvironmentObject var settings: SettingsModel
    
    private var drawerWidth: CGFloat {
        #if os(iOS)
        return min(UIScreen.main.bounds.width * 0.85, 350)
        #elseif os(macOS)
        return 350
        #endif
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Track Segments")
                    .font(.headline)
                    .padding()
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        isDrawerOpen = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .padding(.trailing)
            }
            .background(Color.secondary.opacity(0.1))
            
            Divider()
            
            List {
                ForEach(0..<segments.count, id: \.self) { index in
                    SegmentRow(
                        segment: segments[index],
                        isVisible: $visibleSegments[index],
                        index: index
                    )
                    .environmentObject(settings)
                }
            }
            .listStyle(PlainListStyle())
        }
        .frame(width: drawerWidth)
#if os(iOS)
        .background(Color(PlatformColor.systemBackground))
#elseif os(macOS)
        .background(Color.white)
#endif
        .cornerRadius(10)
        .shadow(radius: 5)
    }
}

struct SegmentRow: View {
    let segment: GPXTrackSegment
    @Binding var isVisible: Bool
    let index: Int
    @EnvironmentObject var settings: SettingsModel
    
    private var elevationStats: (min: Double, max: Double, total: Double) {
        let elevations = segment.locations.map { $0.altitude }
        let min = elevations.min() ?? 0
        let max = elevations.max() ?? 0
        
        var totalAscent: Double = 0
        if elevations.count > 1 {
            for i in 0..<(elevations.count - 1) {
                let diff = elevations[i+1] - elevations[i]
                if diff > 0 {
                    totalAscent += diff
                }
            }
        }
        
        return (min, max, totalAscent)
    }
    
    private var distance: Double {
        var totalDistance: Double = 0
        if segment.locations.count > 1 {
            for i in 0..<(segment.locations.count - 1) {
                totalDistance += segment.locations[i].distance(from: segment.locations[i+1])
            }
        }
        return totalDistance
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Segment \(index + 1)")
                    .font(.headline)
                
                Text("\(segment.locations.count) points")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(settings.formatDistance(distance))")
                    .font(.caption)
                
                let stats = elevationStats
                Text("Elevation: \(Int(stats.min))m - \(Int(stats.max))m")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                isVisible.toggle()
            }) {
                Image(systemName: isVisible ? "eye.fill" : "eye.slash.fill")
                    .foregroundColor(isVisible ? .blue : .gray)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 8)
    }
}

#if DEBUG
struct SegmentListDrawer_Previews: PreviewProvider {
    static var previews: some View {
        SegmentListDrawer(
            segments: .constant([
                GPXTrackSegment(locations: [
                    CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), altitude: 10, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: Date()),
                    CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195), altitude: 15, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: Date())
                ]),
                GPXTrackSegment(locations: [
                    CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.7751, longitude: -122.4196), altitude: 20, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: Date()),
                    CLLocation(coordinate: CLLocationCoordinate2D(latitude: 37.7752, longitude: -122.4197), altitude: 25, horizontalAccuracy: 10, verticalAccuracy: 10, timestamp: Date())
                ])
            ]),
            visibleSegments: .constant([true, false]),
            isDrawerOpen: .constant(true)
        )
        .environmentObject(SettingsModel())
    }
}
#endif