import Foundation
import CoreLocation
import HealthKit

// Represents a track segment with location points
struct GPXTrackSegment: Equatable {
    let locations: [CLLocation]
    let trackIndex: Int  // Reference to which track this segment belongs to
    
    static func == (lhs: GPXTrackSegment, rhs: GPXTrackSegment) -> Bool {
        guard lhs.locations.count == rhs.locations.count && lhs.trackIndex == rhs.trackIndex else { return false }
        
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

// Container for multiple tracks from a single GPX file
// Represents a waypoint (POI) from GPX file
struct GPXWaypoint: Equatable {
    let name: String
    let description: String?
    let coordinate: CLLocationCoordinate2D
    let elevation: Double?
    let timestamp: Date?
    let symbol: String?
    
    static func == (lhs: GPXWaypoint, rhs: GPXWaypoint) -> Bool {
        return lhs.name == rhs.name &&
               lhs.description == rhs.description &&
               lhs.coordinate.latitude == rhs.coordinate.latitude &&
               lhs.coordinate.longitude == rhs.coordinate.longitude &&
               lhs.elevation == rhs.elevation &&
               lhs.timestamp == rhs.timestamp &&
               lhs.symbol == rhs.symbol
    }
}

struct GPXFile {
    let filename: String
    let tracks: [GPXTrack]
    let waypoints: [GPXWaypoint]
    
    // Default initializer with empty waypoints
    init(filename: String, tracks: [GPXTrack], waypoints: [GPXWaypoint] = []) {
        self.filename = filename
        self.tracks = tracks
        self.waypoints = waypoints
    }
    
    // Get the "primary" track for backward compatibility
    var primaryTrack: GPXTrack? {
        tracks.first
    }
    
    // Get all track segments from all tracks
    var allSegments: [GPXTrackSegment] {
        tracks.flatMap { $0.segments }
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
                    let gpxFile = parseGPXFile(at: fileURL)
                    tracks.append(contentsOf: gpxFile.tracks)
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
                let gpxFile = parseGPXFile(at: url)
                tracks.append(contentsOf: gpxFile.tracks)
            }
        }
        
        print("Loaded \(tracks.count) sample tracks from assets")
        return tracks
    }
    
    // Method to load sample waypoints from GPX files
    static func loadSampleWaypoints() -> [GPXWaypoint] {
        var waypoints: [GPXWaypoint] = []
        
        // Look for GPX files in the Samples directory
        let samplesDirPath = Bundle.main.bundlePath + "/Samples"
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: samplesDirPath) {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: samplesDirPath)
                for file in files where file.hasSuffix(".gpx") {
                    let fileURL = URL(fileURLWithPath: samplesDirPath + "/" + file)
                    let gpxFile = parseGPXFile(at: fileURL)
                    waypoints.append(contentsOf: gpxFile.waypoints)
                }
            } catch {
                print("Error reading Samples directory: \(error)")
            }
        }
        
        // Try to find using resource URLs
        if let samplesURLs = Bundle.main.urls(forResourcesWithExtension: "gpx", subdirectory: nil) {
            for url in samplesURLs {
                let gpxFile = parseGPXFile(at: url)
                waypoints.append(contentsOf: gpxFile.waypoints)
            }
        }
        
        print("Loaded \(waypoints.count) sample waypoints from assets")
        return waypoints
    }    
    
    static func parseGPXFile(at url: URL) -> GPXFile {
        // First, check if we have a bookmark for this file already
        var resolvedURL = url
        var securityAccessGranted = false
        
        if let bookmarkData = UserDefaults.standard.data(forKey: "LastGPXBookmark_\(url.lastPathComponent)") {
            do {
                var isStale = false
                let storedURL = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if !isStale && storedURL.startAccessingSecurityScopedResource() {
                    print("Successfully accessed file via existing bookmark for parsing: \(storedURL)")
                    resolvedURL = storedURL
                    securityAccessGranted = true
                } else if isStale {
                    print("Bookmark for \(url.lastPathComponent) is stale, will create a new one")
                    UserDefaults.standard.removeObject(forKey: "LastGPXBookmark_\(url.lastPathComponent)")
                }
            } catch {
                print("Error resolving bookmark for parsing: \(error)")
            }
        }
        
        // If we don't have a bookmark or it failed, try direct access
        if !securityAccessGranted {
            if url.startAccessingSecurityScopedResource() {
                securityAccessGranted = true
                resolvedURL = url
                print("Successfully accessed security-scoped resource for GPX parsing: \(url)")
                
                // Create a bookmark for future use
                do {
                    let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmarkData, forKey: "LastGPXBookmark_\(url.lastPathComponent)")
                    print("Created new bookmark for GPX file: \(url.lastPathComponent)")
                } catch {
                    print("Failed to create bookmark: \(error)")
                }
            }
        }
        
        // Ensure we release access when done
        defer {
            if securityAccessGranted {
                resolvedURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Try to read the data with proper error handling
        var xmlData: Data
        
        do {
            xmlData = try Data(contentsOf: resolvedURL)
        } catch {
            print("Failed to read GPX file at \(resolvedURL): \(error.localizedDescription)")
            
            // Try with file coordination as a fallback
            var fileData: Data?
            var coordError: NSError?
            
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: resolvedURL, options: [], error: &coordError) { coordURL in
                do {
                    fileData = try Data(contentsOf: coordURL)
                } catch let readError {
                    print("Coordinated read also failed: \(readError)")
                }
            }
            
            if let error = coordError {
                print("Coordination error: \(error)")
            }
            
            guard let data = fileData else {
                print("Could not read file data even with coordination")
                return GPXFile(filename: resolvedURL.lastPathComponent, tracks: [], waypoints: [])
            }
            
            xmlData = data
        }
        
        // Extract filename and parse data
        let filename = resolvedURL.deletingPathExtension().lastPathComponent
        let gpxFile = parseGPXData(xmlData, filename: filename)
        
        // Process each track to ensure it has a name
        var namedTracks: [GPXTrack] = []
        
        for (index, var track) in gpxFile.tracks.enumerated() {
            // If track has no name or empty name
            if track.name.isEmpty {
                if gpxFile.tracks.count == 1 {
                    // If only one track, use the filename
                    track.name = filename
                } else {
                    // If multiple tracks, use filename plus track number
                    track.name = "\(filename) - Track \(index + 1)"
                }
                print("Using generated name for track: \(track.name)")
            }
            namedTracks.append(track)
        }
        
        // Log parsing results
        let resultFile = GPXFile(filename: filename, tracks: namedTracks, waypoints: gpxFile.waypoints)
        print("Parsed GPX file \(filename): Found \(resultFile.tracks.count) tracks with \(resultFile.allSegments.count) segments and \(resultFile.waypoints.count) waypoints")
        
        return resultFile
    }
    
    static func parseGPXData(_ data: Data, filename: String = "") -> GPXFile {
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        
        if parser.parse() {
            // Return all parsed tracks and waypoints
            let result = GPXFile(filename: filename, tracks: delegate.tracks, waypoints: delegate.waypoints)
            
            // Success validation - verify we have meaningful data
            if result.tracks.isEmpty && result.waypoints.isEmpty {
                print("Warning: GPX file parsed successfully but no tracks or waypoints found")
            } else if !result.tracks.isEmpty && result.allSegments.isEmpty {
                print("Warning: GPX file has \(result.tracks.count) tracks but no segments")
            } else if !result.tracks.isEmpty && result.allSegments.allSatisfy({ $0.locations.isEmpty }) {
                print("Warning: GPX file has \(result.tracks.count) tracks and \(result.allSegments.count) segments, but no location points")
            }
            
            if !result.waypoints.isEmpty {
                print("Found \(result.waypoints.count) waypoints in GPX file")
            }
            
            return result
        } else {
            // Parse failed - report diagnostic information
            if let error = parser.parserError {
                print("Failed to parse GPX data: \(error.localizedDescription)")
                print("Line: \(parser.lineNumber), Column: \(parser.columnNumber)")
            } else {
                print("Failed to parse GPX data with unknown error")
            }
            
            // Try to detect if this is even a GPX file by checking for typical XML tags
            if let xmlString = String(data: data, encoding: .utf8) {
                if !xmlString.contains("<gpx") {
                    print("Warning: File does not appear to be a GPX file (missing <gpx> tag)")
                } else if !xmlString.contains("<trk") && !xmlString.contains("<wpt") {
                    print("Warning: GPX file does not contain any tracks or waypoints (missing <trk> or <wpt> tags)")
                }
                
                // Log file size and beginning of content for diagnostics
                print("File size: \(data.count) bytes")
                let previewLength = min(100, xmlString.count)
                let preview = String(xmlString.prefix(previewLength))
                print("Content preview: \(preview)...")
            }
            
            return GPXFile(filename: filename, tracks: [], waypoints: [])
        }
    }
}

class GPXParserDelegate: NSObject, XMLParserDelegate {
    private var currentElement = ""
    
    // GPX metadata
    private var gpxMetadataDate = Date()
    
    // Current track data
    private var currentTrackName = ""
    private var currentTrackType = ""
    private var currentTrackDate = Date()
    
    // Current waypoint data
    private var currentWaypointName = ""
    private var currentWaypointDesc: String?
    private var currentWaypointSymbol: String?
    
    // Track the current element context
    private var isTrack = false
    private var isTrackSegment = false
    private var isTrackPoint = false
    private var isMetadata = false
    private var isWaypoint = false
    
    // Data for the current point
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?
    
    // Store segments for the current track
    private var currentSegmentPoints: [CLLocation] = []
    private var currentTrackSegments: [GPXTrackSegment] = []
    
    // Store all completed tracks and waypoints
    private var completedTracks: [GPXTrack] = []
    private var completedWaypoints: [GPXWaypoint] = []
    
    // Public property to access all parsed tracks
    var tracks: [GPXTrack] {
        // Check if we have an in-progress track that needs to be finalized
        finalizeCurrentTrackIfNeeded()
        return completedTracks
    }
    
    // Public property to access all parsed waypoints
    var waypoints: [GPXWaypoint] {
        return completedWaypoints
    }
    
    // Finalize the current track if it has any segments with points
    private func finalizeCurrentTrackIfNeeded() {
        if !currentTrackSegments.isEmpty && !currentTrackSegments.allSatisfy({ $0.locations.isEmpty }) {
            let currentTrackIndex = completedTracks.count
            
            // Update all segments with the correct track index
            let segmentsWithTrackIndex = currentTrackSegments.map { segment in
                GPXTrackSegment(locations: segment.locations, trackIndex: currentTrackIndex)
            }
            
            let track = GPXTrack(
                name: currentTrackName,
                type: currentTrackType,
                date: currentTrackDate.timeIntervalSince1970 > 0 ? currentTrackDate : gpxMetadataDate,
                segments: segmentsWithTrackIndex
            )
            completedTracks.append(track)
            
            // Reset current track data
            currentTrackName = ""
            currentTrackType = ""
            currentTrackDate = Date()
            currentTrackSegments = []
        }
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        switch elementName {
        case "metadata":
            isMetadata = true
            
        case "trk":
            // If we were already processing a track, finalize it
            finalizeCurrentTrackIfNeeded()
            
            isTrack = true
            // Reset for new track
            currentTrackSegments = []
            currentTrackName = ""
            currentTrackType = ""
            currentTrackDate = Date()
            
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
            
        case "wpt":
            isWaypoint = true
            currentLat = Double(attributeDict["lat"] ?? "0")
            currentLon = Double(attributeDict["lon"] ?? "0")
            currentEle = nil
            currentTime = nil
            currentWaypointName = ""
            currentWaypointDesc = nil
            currentWaypointSymbol = nil
            
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
        } else if isWaypoint {
            switch currentElement {
            case "ele":
                currentEle = Double(trimmedString)
            case "time":
                let formatter = ISO8601DateFormatter()
                currentTime = formatter.date(from: trimmedString)
            case "name":
                currentWaypointName = trimmedString
            case "desc":
                currentWaypointDesc = trimmedString
            case "sym":
                currentWaypointSymbol = trimmedString
            default:
                break
            }
        } else if isTrack {
            switch currentElement {
            case "name":
                currentTrackName = trimmedString
            case "type":
                currentTrackType = trimmedString
            case "time":
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: trimmedString) {
                    currentTrackDate = date
                }
            default:
                break
            }
        } else if isMetadata {
            // Handle metadata elements
            switch currentElement {
            case "time":
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: trimmedString) {
                    gpxMetadataDate = date
                }
            default:
                break
            }
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "metadata":
            isMetadata = false
            
        case "trkpt":
            if isTrackPoint, let lat = currentLat, let lon = currentLon {
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
            
        case "wpt":
            if isWaypoint, let lat = currentLat, let lon = currentLon {
                let waypoint = GPXWaypoint(
                    name: currentWaypointName.isEmpty ? "POI" : currentWaypointName,
                    description: currentWaypointDesc,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    elevation: currentEle,
                    timestamp: currentTime,
                    symbol: currentWaypointSymbol
                )
                completedWaypoints.append(waypoint)
            }
            isWaypoint = false
            
        case "trkseg":
            // End of segment - add it to the current track's segments
            if !currentSegmentPoints.isEmpty {
                // Use a placeholder track index that will be updated in finalizeCurrentTrackIfNeeded
                let segment = GPXTrackSegment(locations: currentSegmentPoints, trackIndex: -1)
                currentTrackSegments.append(segment)
            }
            isTrackSegment = false
            
        case "trk":
            // End of track - finalize it
            finalizeCurrentTrackIfNeeded()
            isTrack = false
            
        case "gpx":
            // End of file - make sure we've finalized any in-progress track
            finalizeCurrentTrackIfNeeded()
            
        default:
            break
        }
        
        currentElement = ""
    }
    
    // Legacy support for single track
    var track: GPXTrack? {
        return tracks.first
    }
}
