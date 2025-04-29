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
    var track: GPXTrack?
    var trackSegments: [GPXTrackSegment] = []
    
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
        if let parsedTrack = GPXParser.parseGPXData(data) {
            track = parsedTrack
            trackSegments = parsedTrack.segments
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}
