import SwiftUI
import CoreLocation

struct TracksDrawer: View {
    @Binding var isOpen: Bool
    @Binding var document: GPXViewerDocument
    @Binding var visibleSegments: [Bool]
    @Binding var selectedTrackIndex: Int
    @Binding var segments: [GPXTrackSegment]
    @EnvironmentObject var settings: SettingsModel
    
    // Helper function to calculate segment length
    private func calculateSegmentLength(_ locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }
        
        var totalDistance: Double = 0
        for i in 0..<(locations.count - 1) {
            totalDistance += locations[i].distance(from: locations[i+1])
        }
        
        return totalDistance
    }
    
    // Helper function to toggle segment visibility
    private func toggleAllSegments() {
        let allVisible = visibleSegments.allSatisfy { $0 }
        // If all are visible, hide all; otherwise show all
        for i in 0..<visibleSegments.count {
            visibleSegments[i] = !allVisible
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // Header
            HStack {
                Text("Tracks & Segments")
                    .font(.headline)
                    .padding(.vertical, 8)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        isOpen = false
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal)
            
            // Toggle all segments button
            Button(action: {
                toggleAllSegments()
            }) {
                HStack {
                    Image(systemName: visibleSegments.allSatisfy { $0 } ? "eye.slash" : "eye")
                    Text(visibleSegments.allSatisfy { $0 } ? "Hide All" : "Show All")
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal)
            
            Divider()
                .padding(.vertical, 4)
            
            // List of tracks and segments
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<document.tracks.count, id: \.self) { trackIndex in
                        let track = document.tracks[trackIndex]
                        
                        // Track header
                        HStack {
                            Text(track.name.isEmpty ? "Track \(trackIndex + 1)" : track.name)
                                .fontWeight(.bold)
                                .padding(.vertical, 6)
                            
                            Spacer()
                            
                            Button(action: {
                                selectedTrackIndex = trackIndex
                            }) {
                                Image(systemName: selectedTrackIndex == trackIndex ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedTrackIndex == trackIndex ? .blue : .gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                        
                        // Segments within this track
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(0..<segments.count, id: \.self) { index in
                                if segments[index].trackIndex == trackIndex {
                                    let segment = segments[index]
                                    let pointCount = segment.locations.count
                                    
                                    // Only show rows for segments with points
                                    if pointCount > 0 {
                                        HStack {
                                            // Visibility toggle
                                            Button(action: {
                                                visibleSegments[index].toggle()
                                            }) {
                                                Image(systemName: visibleSegments[index] ? "eye" : "eye.slash")
                                                    .foregroundColor(visibleSegments[index] ? .blue : .gray)
                                                    .frame(width: 24, height: 24)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            
                                            // Segment info
                                            VStack(alignment: .leading) {
                                                Text("Segment \(index + 1)")
                                                    .fontWeight(.medium)
                                                
                                                Text("\(pointCount) points")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                
                                                // Show segment length
                                                if pointCount > 1 {
                                                    let length = calculateSegmentLength(segment.locations)
                                                    Text(settings.formatDistance(length))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            
                                            Spacer()
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal)
                                        .background(visibleSegments[index] ? Color.blue.opacity(0.1) : Color.clear)
                                        .cornerRadius(8)
                                        .padding(.horizontal, 12)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 8)
                        
                        Divider()
                            .padding(.vertical, 4)
                    }
                }
                .padding(.bottom)
            }
        }
        .frame(width: 280)
        .background(Color.white.opacity(0.98))
        #if os(iOS)
        .border(Color.gray.opacity(0.2), width: 1)
        #endif
        .transition(.move(edge: .trailing))
    }
}

#Preview {
    TracksDrawer(
        isOpen: .constant(true),
        document: .constant(GPXViewerDocument()),
        visibleSegments: .constant([]),
        selectedTrackIndex: .constant(0),
        segments: .constant([])
    )
    .environmentObject(SettingsModel())
}
