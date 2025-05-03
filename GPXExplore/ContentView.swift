//
//  ContentView.swift
//  GPXViewer
//
//  Created by Gavi Narra on 4/29/25.
//

import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @Binding var document: GPXViewerDocument
    @StateObject private var settings = SettingsModel()
    @State private var isTracksDrawerOpen = false
    @State private var visibleSegments: [Bool] = []
    @State private var selectedTrackIndex: Int = 0
    @State private var segments: [GPXTrackSegment] = []
    @State private var waypointsVisible: Bool = true
    
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
                            waypoints: waypointsVisible ? document.waypoints : []
                        )
                        .environmentObject(settings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Overlay with route information
                        if let track = selectedTrack {
                            RouteInfoOverlay(trackSegments: visibleTrackSegments, workout: track.workout)
                                .environmentObject(settings)
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
                            waypointsVisible: $waypointsVisible
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
            
            // Tracks drawer toggle
            ToolbarItem(placement: .automatic) {
                TracksDrawer.toolbarButton(isOpen: $isTracksDrawerOpen)
            }
        }
    }
}

#Preview {
    ContentView(document: .constant(GPXViewerDocument()))
}
