//
//  GPXViewerDocument.swift
//  GPXViewer
//
//  Created by Gavi Narra on 4/29/25.
//

import SwiftUI
import UniformTypeIdentifiers
import CoreLocation
import MapKit

extension UTType {
    static var gpx: UTType {
        UTType(importedAs: "com.topografix.gpx")
    }
}

struct GPXViewerDocument: FileDocument {
    var text: String
    var gpxFile: GPXFile?
    
    // For backward compatibility and UI convenience
    var track: GPXTrack? {
        return gpxFile?.primaryTrack
    }
    
    var tracks: [GPXTrack] {
        return gpxFile?.tracks ?? []
    }
    
    var trackSegments: [GPXTrackSegment] {
        return gpxFile?.allSegments ?? []
    }
    
    init(text: String = "") {
        self.text = text
    }

    static var readableContentTypes: [UTType] { 
        [UTType.gpx, UTType.xml] 
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
        
        // Parse GPX data
        let filename = configuration.file.filename ?? "Unknown"
        self.gpxFile = GPXParser.parseGPXData(data, filename: filename)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}
