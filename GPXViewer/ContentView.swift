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
    @State private var isSegmentDrawerOpen = false
    @State private var visibleSegments: [Bool] = []
    @State private var selectedTrackIndex: Int = 0
    @State private var segments: [GPXTrackSegment] = []
    
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
                
                // Main content as a horizontal split view with animation
                HStack(spacing: 0) {
                    // Map content on the left
                    ZStack {
                        // Map view as the base layer
                        MapView(trackSegments: visibleTrackSegments)
                            .environmentObject(settings)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Overlay with route information
                        if let track = selectedTrack {
                            RouteInfoOverlay(trackSegments: visibleTrackSegments, workout: track.workout)
                                .environmentObject(settings)
                        }
                    }
                    
                    // Tracks drawer on the right (only shown when open)
                    if isSegmentDrawerOpen {
                        TracksDrawer(
                            isOpen: $isSegmentDrawerOpen,
                            document: $document,
                            visibleSegments: $visibleSegments,
                            selectedTrackIndex: $selectedTrackIndex,
                            segments: $segments
                        )
                        .environmentObject(settings)
                    }
                    
                    // Toggle button (visible only when drawer is closed)
                    if !isSegmentDrawerOpen {
                        VStack {
                            Spacer()
                            
                            Button(action: {
                                withAnimation {
                                    isSegmentDrawerOpen = true
                                }
                            }) {
                                VStack(alignment: .center, spacing: 5) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14))
                                    Text("Tracks")
                                        .font(.caption)
                                        .rotated(.degrees(-90))
                                        .fixedSize()
                                }
                                .foregroundColor(.primary)
                                .padding(.vertical, 24)
                                .padding(.horizontal, 6)
                                .background(Color.white.opacity(0.9))
                                .cornerRadius(8)
                                .shadow(radius: 2)
                            }
                            .padding()
                            
                            Spacer()
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isSegmentDrawerOpen)
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
            ToolbarItem(placement: .automatic) {
                Picker("Map Style", selection: $settings.mapStyle) {
                    ForEach(MapStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

#Preview {
    ContentView(document: .constant(GPXViewerDocument()))
}
