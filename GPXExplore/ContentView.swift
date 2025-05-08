import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @Binding var document: GPXExploreDocument
    @StateObject private var settings = SettingsModel()
    @State private var isTracksDrawerOpen = false
    @State private var isSettingsPresented = false
    @State private var visibleSegments: [Bool] = []
    @State private var selectedTrackIndex: Int = 0
    @State private var segments: [GPXTrackSegment] = []
    @State private var waypointsVisible: Bool = true
    @State private var selectedWaypointIndex: Int = -1 // -1 indicates no selection
    @State private var selectedWaypointCoordinate: CLLocationCoordinate2D? = nil
    @State private var triggerSpanView: Bool = false
    
    private func updateFromDocument() {
        segments = document.trackSegments
        if visibleSegments.count != segments.count {
            visibleSegments = Array(repeating: true, count: segments.count)
        }
    }
    
    private var visibleTrackSegments: [GPXTrackSegment] {
        // Filter segments based on visibility
        return zip(segments, visibleSegments)
            .filter { $0.1 }  // Keep only visible segments
            .map { $0.0 }     // Return just the segment
    }
    
    private var selectedTrack: GPXTrack? {
        guard !document.tracks.isEmpty else { return nil }
        if document.tracks.indices.contains(selectedTrackIndex) {
            return document.tracks[selectedTrackIndex]
        } else {
            // Reset to first track if index is invalid
            selectedTrackIndex = 0
            return document.tracks.first
        }
    }
    
    // Create a workout based on visible segments
    private func createWorkoutFromSegments(_ segments: [GPXTrackSegment], originalTrack: GPXTrack) -> GPXWorkout {
        // Combine all locations from visible segments
        let allLocations = segments.flatMap { $0.locations }
        
        // If no visible segments, return the original workout
        if allLocations.isEmpty {
            return originalTrack.workout
        }
        
        // Sort locations by timestamp to get accurate start/end times
        let sortedLocations = allLocations.sorted { $0.timestamp < $1.timestamp }
        
        // Extract start and end dates from visible locations
        let startDate = sortedLocations.first?.timestamp ?? originalTrack.workout.startDate
        let endDate = sortedLocations.last?.timestamp ?? originalTrack.workout.endDate
        
        // Calculate total distance from visible segments
        var totalDistanceMeters: Double = 0
        if allLocations.count > 1 {
            for i in 0..<(allLocations.count - 1) {
                totalDistanceMeters += allLocations[i].distance(from: allLocations[i+1])
            }
        }
        
        // Create a new workout with data just from visible segments
        return GPXWorkout(
            activityType: originalTrack.activityType,
            startDate: startDate,
            endDate: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalDistance: totalDistanceMeters,
            metadata: originalTrack.workout.metadata
        )
    }

    var body: some View {
        ZStack {
            if !document.trackSegments.isEmpty {
                // Initialize data from document
                Color.clear
                    .onAppear {
                        updateFromDocument()
                    }
                    .onChange(of: document.trackSegments.count) { _ in
                        updateFromDocument()
                    }
                
                // Main content with optional drawer
                HStack(spacing: 0) {
                    // Main map content
                    ZStack {
                        // Map view as the base layer
                        MapView(
                            trackSegments: visibleTrackSegments,
                            waypoints: waypointsVisible ? document.waypoints : [],
                            centerCoordinate: selectedWaypointCoordinate,
                            zoomLevel: 0.005, // Closer zoom when centering on a waypoint
                            spanAll: triggerSpanView // Trigger to span view to all visible content
                        )
                        .environmentObject(settings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: triggerSpanView) { newValue in
                            if newValue {
                                // Reset the trigger after it's been used
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    triggerSpanView = false
                                }
                            }
                        }
                        
                        // Overlay with route information
                        if let track = selectedTrack {
                            // Create a workout based only on visible segments
                            let visibleWorkout = createWorkoutFromSegments(visibleTrackSegments, originalTrack: track)
                            RouteInfoOverlay(trackSegments: visibleTrackSegments, workout: visibleWorkout)
                                .environmentObject(settings)
                        }
                    }
                    #if os(iOS) || os(visionOS)
                    .toolbar(.visible, for: .navigationBar)
                    #endif
                    .toolbar {
                        // Map style picker
                        ToolbarItem(placement: .automatic) {
                            Picker("Map Style", selection: $settings.mapStyle) {
                                ForEach(MapStyle.allCases) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        // Settings button
                        ToolbarItem(placement: .automatic) {
                            Button(action: {
                                isSettingsPresented = true
                            }) {
                                Label("Settings", systemImage: "gear")
                            }
                        }
                        
                        // Span to fit button
                        ToolbarItem(placement: .automatic) {
                            Button(action: {
                                // Clear any selected waypoint first
                                selectedWaypointCoordinate = nil
                                // Trigger the span view
                                triggerSpanView = true
                            }) {
                                Label("Fit to View", systemImage: "arrow.up.left.and.arrow.down.right")
                            }
                        }
                        
                        // Tracks drawer toggle
                        ToolbarItem(placement: .automatic) {
                            TracksDrawer.toolbarButton(isOpen: $isTracksDrawerOpen)
                        }
                    }
                    .sheet(isPresented: $isSettingsPresented) {
                        NavigationStack {
                            SettingsView()
                                .environmentObject(settings)
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("Done") {
                                            isSettingsPresented = false
                                        }
                                    }
                                }
                        }
                    }
                    
                    // Tracks drawer on the right (only shown when open)
                    if isTracksDrawerOpen {
                        TracksDrawer(
                            isOpen: $isTracksDrawerOpen,
                            document: $document,
                            visibleSegments: $visibleSegments,
                            selectedTrackIndex: $selectedTrackIndex,
                            segments: $segments,
                            waypointsVisible: $waypointsVisible,
                            selectedWaypointIndex: $selectedWaypointIndex,
                            onWaypointSelected: { coordinate in
                                // Update the state to center on this waypoint
                                selectedWaypointCoordinate = coordinate
                            }
                        )
                        .environmentObject(settings)
                        .transition(.move(edge: .trailing))
                    }
                }
            } else {
                VStack {
                    Text("No valid GPX data found")
                        .font(.title)
                        .padding()
                    
                    Text("Open a GPX file to view the track on the map")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    ContentView(document: .constant(GPXExploreDocument()))
}
