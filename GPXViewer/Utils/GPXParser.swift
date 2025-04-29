import Foundation
import CoreLocation
import HealthKit

// Represents a track segment with location points
struct GPXTrackSegment: Equatable {
    let locations: [CLLocation]
    
    static func == (lhs: GPXTrackSegment, rhs: GPXTrackSegment) -> Bool {
        guard lhs.locations.count == rhs.locations.count else { return false }
        
        for i in 0..<lhs.locations.count {
            let loc1 = lhs.locations[i]
            let loc2 = rhs.locations[i]
            
            // Compare essential properties
            if loc1.coordinate.latitude != loc2.coordinate.latitude ||
               loc1.coordinate.longitude != loc2.coordinate.longitude ||
               loc1.altitude != loc2.altitude ||
               loc1.timestamp != loc2.timestamp {
                return false
            }
        }
        
        return true
    }
}

struct GPXTrack {
    var name: String
    let type: String
    let date: Date
    // Updated to support multiple track segments
    let segments: [GPXTrackSegment]
    
    // Convenience computed property to get all locations across all segments
    var allLocations: [CLLocation] {
        return segments.flatMap { $0.locations }
    }
    
    var workoutType: HKWorkoutActivityType {
        // Check filename first for simulator samples
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("run") || lowercaseName.contains("running") {
            return .running
        } else if lowercaseName.contains("bike") || lowercaseName.contains("cycling") {
            return .cycling
        } else if lowercaseName.contains("hike") || lowercaseName.contains("hiking") {
            return .hiking
        }
        
        // Then check type field
        switch type.lowercased() {
        case "running":
            return .running
        case "cycling":
            return .cycling
        case "hiking":
            return .hiking
        default:
            // Default to running for simulator testing
            #if targetEnvironment(simulator)
                return .running
            #else
                return .other
            #endif
        }
    }
    
    var workout: HKWorkout {
        // Create a workout representation for the GPX track
        // Use sorted locations to ensure start and end dates are correct
        let allLocations = self.allLocations
        let sortedLocations = allLocations.sorted { $0.timestamp < $1.timestamp }
        
        // Make sure we have valid dates (start date must be before end date)
        var startDate = sortedLocations.first?.timestamp ?? date
        var endDate = sortedLocations.last?.timestamp ?? date.addingTimeInterval(3600)
        
        // Ensure end date is after start date
        if endDate <= startDate {
            // If timestamps are invalid, use the current date with a 1-hour duration
            startDate = Date()
            endDate = startDate.addingTimeInterval(3600)
        }
        
        // Calculate total distance by summing distances between consecutive points
        var totalDistanceMeters: Double = 0
        if allLocations.count > 1 {
            for i in 0..<(allLocations.count - 1) {
                totalDistanceMeters += allLocations[i].distance(from: allLocations[i+1])
            }
        }
        
        let totalDistanceQuantity = HKQuantity(unit: .meter(), doubleValue: totalDistanceMeters)
        
        return HKWorkout(
            activityType: workoutType,
            start: startDate,
            end: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalEnergyBurned: nil,
            totalDistance: totalDistanceQuantity,
            metadata: [
                "name": name,
                "source": "GPX Sample"
            ]
        )
    }
}

class GPXParser {
    
    static func loadSampleTracks() -> [GPXTrack] {
        var tracks: [GPXTrack] = []
        
        // Look for GPX files in the Samples directory
        let samplesDirPath = Bundle.main.bundlePath + "/Samples"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: samplesDirPath) {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: samplesDirPath)
                for file in files where file.hasSuffix(".gpx") {
                    let fileURL = URL(fileURLWithPath: samplesDirPath + "/" + file)
                    print("Loading sample from: \(fileURL.lastPathComponent)")
                    if let track = parseGPXFile(at: fileURL) {
                        tracks.append(track)
                    }
                }
            } catch {
                print("Error reading Samples directory: \(error)")
            }
        } else {
            print("Samples directory not found in bundle path")
        }
        
        // Try to find using resource URLs
        if let samplesURLs = Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: nil) {
            print("Found \(samplesURLs.count) gpx files via Bundle.main.urls")
            for url in samplesURLs {
                print("Loading sample from: \(url.lastPathComponent)")
                if let track = parseGPXFile(at: url) {
                    tracks.append(track)
                }
            }
        }
        
        print("Loaded \(tracks.count) sample tracks from assets")
        return tracks
    }    
    static func parseGPXFile(at url: URL) -> GPXTrack? {
        guard let xmlData = try? Data(contentsOf: url) else {
            print("Failed to read GPX file at \(url)")
            return nil
        }
        
        var track = parseGPXData(xmlData)
        
        // If track has no name or empty name, use the filename without extension
        if track?.name.isEmpty ?? true {
            let filename = url.deletingPathExtension().lastPathComponent
            track?.name = filename
            print("Using filename as track name: \(filename)")
        }
        
        return track
    }
    
    static func parseGPXData(_ data: Data) -> GPXTrack? {
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        
        if parser.parse() {
            // If there's no name in the GPX file, use the filename without extension
            if delegate.track?.name.isEmpty ?? true {
                // We can't set the name here since we don't have the filename
                // The calling code will need to handle this
                print("No name found in GPX data")
            }
            return delegate.track
        } else {
            print("Failed to parse GPX data")
            return nil
        }
    }
}

class GPXParserDelegate: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var trackName = ""
    private var trackType = ""
    private var trackDate = Date()
    
    // Track the current track, segment, and point
    private var isTrack = false
    private var isTrackSegment = false
    private var isTrackPoint = false
    
    // Data for the current point
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?
    
    // Store segments for the current track
    private var currentSegmentPoints: [CLLocation] = []
    private var segments: [GPXTrackSegment] = []
    
    var track: GPXTrack? {
        // Only return a track if we have at least one segment with points
        if segments.isEmpty || segments.allSatisfy({ $0.locations.isEmpty }) {
            return nil
        }
        return GPXTrack(
            name: trackName,
            type: trackType,
            date: trackDate,
            segments: segments
        )
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        switch elementName {
        case "trk":
            isTrack = true
            // Reset segments when starting a new track
            segments = []
            
        case "trkseg":
            isTrackSegment = true
            // Reset current segment points
            currentSegmentPoints = []
            
        case "trkpt":
            isTrackPoint = true
            currentLat = Double(attributeDict["lat"] ?? "0")
            currentLon = Double(attributeDict["lon"] ?? "0")
            currentEle = nil
            currentTime = nil
            
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty else { return }
        
        if isTrackPoint {
            switch currentElement {
            case "ele":
                currentEle = Double(trimmedString)
            case "time":
                let formatter = ISO8601DateFormatter()
                currentTime = formatter.date(from: trimmedString)
            default:
                break
            }
        } else {
            switch currentElement {
            case "name":
                // Only set track name if we're in a track element
                if isTrack {
                    trackName = trimmedString
                }
            case "type":
                trackType = trimmedString
            case "time":
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: trimmedString) {
                    trackDate = date
                }
            default:
                break
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "trkpt" && isTrackPoint {
            if let lat = currentLat, let lon = currentLon {
                let location = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    altitude: currentEle ?? 0,
                    horizontalAccuracy: 10,
                    verticalAccuracy: 10,
                    timestamp: currentTime ?? Date()
                )
                currentSegmentPoints.append(location)
            }
            isTrackPoint = false
        } else if elementName == "trkseg" {
            // End of segment - add it to the list of segments
            let segment = GPXTrackSegment(locations: currentSegmentPoints)
            segments.append(segment)
            isTrackSegment = false
        } else if elementName == "trk" {
            isTrack = false
        }
        
        currentElement = ""
    }
}
