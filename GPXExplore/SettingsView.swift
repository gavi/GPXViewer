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
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsModel())
}
