//
//  SettingsView.swift
//  GPXExplore
//
//  Created by Gavi Narra on 5/4/25.
//


import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        Form {
            Section(header: Text("Units")) {
                Toggle("Use Metric System (km)", isOn: $settings.useMetricSystem)
            }
            
            Section(header: Text("Map")) {
                Picker("Map Style", selection: $settings.mapStyle) {
                    ForEach(MapStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Section(header: Text("Elevation Visualization")) {
                Picker("Visualization Mode", selection: $settings.elevationVisualizationMode) {
                    ForEach(ElevationVisualizationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Text(settings.elevationVisualizationMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                
                Divider()
                    .padding(.vertical, 8)
                
                Toggle("Show Elevation Chart by Default", isOn: $settings.defaultShowElevationOverlay)
                    .padding(.vertical, 4)
                
                Text("Controls whether the elevation chart overlay appears by default when opening GPX files")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
                
                Divider()
                    .padding(.vertical, 8)
                
                Text("Track Line Width: \(Int(settings.trackLineWidth))")
                
                Slider(
                    value: $settings.trackLineWidth,
                    in: 2...10,
                    step: 1
                ) {
                    Text("Track Line Width")
                } minimumValueLabel: {
                    Text("2")
                } maximumValueLabel: {
                    Text("10")
                }
                
                Text("Adjust the thickness of track lines on the map")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsModel())
}
