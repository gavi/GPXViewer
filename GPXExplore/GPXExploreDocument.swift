//
//  GPXExploreDocument.swift
//  GPXExplore
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

struct GPXExploreDocument: FileDocument {
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
    
    var waypoints: [GPXWaypoint] {
        return gpxFile?.waypoints ?? []
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
            // Log more details about failure
            print("Failed to read file contents or decode as UTF-8")
            print("File type: \(configuration.contentType)")
            print("File name: \(configuration.file.filename ?? "Unknown")")
            
            if let fileData = configuration.file.regularFileContents {
                print("File size: \(fileData.count) bytes")
                // Try other encodings if UTF-8 failed
                for encoding in [String.Encoding.ascii, .utf16, .isoLatin1, .windowsCP1252] {
                    if let _ = String(data: fileData, encoding: encoding) {
                        print("File could be decoded using \(encoding) encoding")
                    }
                }
            } else {
                print("No file data available")
            }
            
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
        
        // Parse GPX data
        let filename = configuration.file.filename ?? "Unknown"
        self.gpxFile = GPXParser.parseGPXData(data, filename: filename)
        
        // Log whether parsing was successful
        if let gpxFile = self.gpxFile {
            print("Successfully parsed GPX file: \(filename)")
            print("Found \(gpxFile.tracks.count) tracks with \(gpxFile.allSegments.count) total segments and \(gpxFile.waypoints.count) waypoints")
        } else {
            print("Failed to parse GPX data from \(filename)")
        }
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}
