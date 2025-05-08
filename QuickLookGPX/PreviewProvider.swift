//
//  PreviewProvider.swift
//  QuickLookGPX
//
//  Created by Gavi Narra on 5/8/25.
//

import Cocoa
import Quartz
import MapKit
import CoreLocation
import AppKit
import PDFKit

class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL
        
        // Parse the GPX file using our parser
        let gpxFile = GPXParser.parseGPXFile(at: fileURL)
        
        // Check if we have tracks to display
        guard !gpxFile.tracks.isEmpty else {
            throw NSError(domain: "QuickLookGPX", code: 2, userInfo: [NSLocalizedDescriptionKey: "No tracks found in GPX file"])
        }
        
        // Create PDF data with track information
        let pdfData = createSimplePDF(from: gpxFile)
        
        // Create a preview reply with the PDF data
        return QLPreviewReply(dataOfContentType: UTType.pdf, contentSize: CGSize(width: 800, height: 600)) { _ in
            return pdfData
        }
    }
    
    // Create a simpler PDF that doesn't depend on map rendering
    private func createSimplePDF(from file: GPXFile) -> Data {
        // Create a PDF document
        let pdfData = NSMutableData()
        
        // Create a PDF context
        let pageRect = CGRect(x: 0, y: 0, width: 800, height: 600)
        var mediaBox = pageRect
        let context = CGContext(consumer: CGDataConsumer(data: pdfData)!, mediaBox: &mediaBox, nil)!
        
        // Start the first page
        context.beginPDFPage(nil)
        
        // Set up text attributes
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]
        
        let headingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]
        
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black
        ]
        
        // Draw title
        let title = file.filename
        let titleString = NSAttributedString(string: "GPX File: \(title)", attributes: titleAttributes)
        titleString.draw(at: CGPoint(x: 50, y: 550))
        
        // Draw track summary
        let trackCount = file.tracks.count
        let waypoints = file.waypoints.count
        let summaryString = NSAttributedString(
            string: "Track Summary", 
            attributes: headingAttributes
        )
        summaryString.draw(at: CGPoint(x: 50, y: 500))
        
        let infoString = NSAttributedString(
            string: "• Number of tracks: \(trackCount)\n• Number of waypoints: \(waypoints)",
            attributes: textAttributes
        )
        infoString.draw(at: CGPoint(x: 50, y: 480))
        
        // Calculate statistics for all tracks
        var totalDistance = 0.0
        var totalTime: TimeInterval = 0
        var totalAscent = 0.0
        var totalDescent = 0.0
        
        for track in file.tracks {
            // Add distance and time
            let workout = track.workout
            totalDistance += workout.totalDistance
            totalTime += workout.duration
            
            // Calculate elevation
            for segment in track.segments {
                if segment.locations.count > 1 {
                    for i in 1..<segment.locations.count {
                        let elevDiff = segment.locations[i].altitude - segment.locations[i-1].altitude
                        if elevDiff > 1.0 {
                            totalAscent += elevDiff
                        } else if elevDiff < -1.0 {
                            totalDescent += abs(elevDiff)
                        }
                    }
                }
            }
        }
        
        // Format statistics
        let statsHeading = NSAttributedString(
            string: "Statistics", 
            attributes: headingAttributes
        )
        statsHeading.draw(at: CGPoint(x: 50, y: 430))
        
        // Format distance
        let distanceFormatter = MeasurementFormatter()
        distanceFormatter.unitOptions = .providedUnit
        distanceFormatter.numberFormatter.maximumFractionDigits = 1
        
        let distanceMeasurement = Measurement(value: totalDistance, unit: UnitLength.meters)
        let formattedDistance = distanceFormatter.string(from: distanceMeasurement)
        
        // Format time
        let timeFormatter = DateComponentsFormatter()
        timeFormatter.allowedUnits = [.hour, .minute, .second]
        timeFormatter.unitsStyle = .abbreviated
        let formattedTime = timeFormatter.string(from: totalTime) ?? "Unknown"
        
        // Format elevation
        let elevFormatter = MeasurementFormatter()
        elevFormatter.unitOptions = .providedUnit
        elevFormatter.numberFormatter.maximumFractionDigits = 0
        
        let ascentMeasurement = Measurement(value: totalAscent, unit: UnitLength.meters)
        let descentMeasurement = Measurement(value: totalDescent, unit: UnitLength.meters)
        
        let formattedAscent = elevFormatter.string(from: ascentMeasurement)
        let formattedDescent = elevFormatter.string(from: descentMeasurement)
        
        // Draw statistics
        let statsString = NSAttributedString(
            string: "• Distance: \(formattedDistance)\n• Duration: \(formattedTime)\n• Elevation Gain: \(formattedAscent)\n• Elevation Loss: \(formattedDescent)",
            attributes: textAttributes
        )
        statsString.draw(at: CGPoint(x: 50, y: 410))
        
        // Track information section
        let tracksHeading = NSAttributedString(
            string: "Track Details", 
            attributes: headingAttributes
        )
        tracksHeading.draw(at: CGPoint(x: 50, y: 350))
        
        var yPosition = 330.0
        
        for (index, track) in file.tracks.enumerated() {
            // Track name and type
            let trackTitle = NSAttributedString(
                string: "Track \(index + 1): \(track.name)",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.black]
            )
            trackTitle.draw(at: CGPoint(x: 50, y: yPosition))
            yPosition -= 20
            
            // Track details
            let trackDetailsString = NSAttributedString(
                string: "• Type: \(track.type)\n• Segments: \(track.segments.count)\n• Points: \(track.allLocations.count)",
                attributes: textAttributes
            )
            trackDetailsString.draw(at: CGPoint(x: 50, y: yPosition))
            yPosition -= 60
            
            // Don't go off page
            if yPosition < 100 {
                break
            }
        }
        
        // Footer
        let footerString = NSAttributedString(
            string: "Generated by GPXExplore Quick Look Extension",
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .light), .foregroundColor: NSColor.gray]
        )
        footerString.draw(at: CGPoint(x: 50, y: 50))
        
        // End page and close PDF
        context.endPDFPage()
        context.closePDF()
        
        return pdfData as Data
    }
}