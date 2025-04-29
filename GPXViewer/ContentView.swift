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
    
    private func initializeVisibleSegments() {
        if visibleSegments.count != document.trackSegments.count {
            visibleSegments = Array(repeating: true, count: document.trackSegments.count)
        }
    }
    
    private var visibleTrackSegments: [GPXTrackSegment] {
        // Filter segments based on visibility
        return zip(document.trackSegments, visibleSegments)
            .filter { $0.1 }  // Keep only visible segments
            .map { $0.0 }     // Return just the segment
    }

    var body: some View {
        ZStack {
            if !document.trackSegments.isEmpty {
                // Map view content
                ZStack {
                    // Empty view just for the modifiers
                    Color.clear
                        .onAppear {
                            initializeVisibleSegments()
                        }
                        .onChange(of: document.trackSegments.count) { _ in
                            initializeVisibleSegments()
                        }
                
                    // Map view as the base layer
                    MapView(trackSegments: visibleTrackSegments)
                        .environmentObject(settings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Overlay with route information
                if let track = document.track {
                    RouteInfoOverlay(trackSegments: visibleTrackSegments, workout: track.workout)
                        .environmentObject(settings)
                }
                
                // Segment drawer overlay (when open)
                if isSegmentDrawerOpen {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                isSegmentDrawerOpen = false
                            }
                        }
                    
                    VStack {
                        Spacer()
                        
                        HStack {
                            Spacer()
                            
                            SegmentListDrawer(
                                segments: $document.trackSegments,
                                visibleSegments: $visibleSegments,
                                isDrawerOpen: $isSegmentDrawerOpen
                            )
                            .environmentObject(settings)
                            .transition(.move(edge: .trailing))
                        }
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
            ToolbarItem(placement: .automatic) {
                Picker("Map Style", selection: $settings.mapStyle) {
                    ForEach(MapStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    withAnimation {
                        isSegmentDrawerOpen.toggle()
                    }
                }) {
                    Image(systemName: "list.bullet")
                        .foregroundColor(isSegmentDrawerOpen ? .accentColor : nil)
                }
                .disabled(document.trackSegments.isEmpty)
            }
        }
    }
}

#Preview {
    ContentView(document: .constant(GPXViewerDocument()))
}
