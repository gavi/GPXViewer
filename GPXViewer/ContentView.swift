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

    var body: some View {
        ZStack {
            if !document.trackSegments.isEmpty {
                // Map view as the base layer
                MapView(trackSegments: document.trackSegments)
                    .environmentObject(settings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Overlay with route information
                if let track = document.track {
                    RouteInfoOverlay(trackSegments: document.trackSegments, workout: track.workout)
                        .environmentObject(settings)
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
        }
    }
}

#Preview {
    ContentView(document: .constant(GPXViewerDocument()))
}
