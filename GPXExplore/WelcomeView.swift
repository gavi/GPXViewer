import SwiftUI
import UniformTypeIdentifiers
import MapKit

struct WelcomeView: View {
    @EnvironmentObject var recentFilesManager: RecentFilesManager
    @State private var isShowingFileImporter = false
    @State private var selectedTabIndex = 0
    
    // Sample map data to show in the background
    private let sampleCoordinates = [
        CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
        CLLocationCoordinate2D(latitude: 47.6152, longitude: -122.3447),
        CLLocationCoordinate2D(latitude: 47.6302, longitude: -122.3553),
        CLLocationCoordinate2D(latitude: 47.6390, longitude: -122.3614)
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar with actions
            VStack(spacing: 20) {
                Image(systemName: "map.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                    .padding(.top, 50)
                
                Text("GPXExplore")
                    .font(.title2)
                    .bold()
                
                Spacer()
                    .frame(height: 20)
                
                TabBar(selectedIndex: $selectedTabIndex)
                    .padding(.horizontal, 20)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    // Create new document button (opens file picker)
                    ActionButton(
                        title: "Open GPX File",
                        icon: "doc.badge.plus",
                        action: { isShowingFileImporter = true }
                    )
                    
                    // Visit website button
                    ActionButton(
                        title: "Visit Website",
                        icon: "safari",
                        action: {
                            #if os(macOS)
                            NSWorkspace.shared.open(URL(string: "https://gpxexplore.app")!)
                            #else
                            UIApplication.shared.open(URL(string: "https://gpxexplore.app")!)
                            #endif
                        }
                    )
                }
                .padding(.bottom, 50)
            }
            .frame(width: 220)
            .background(Color(.windowBackgroundColor).opacity(0.8))
            
            // Main content area
            ZStack {
                // Background map (static for welcome screen)
                #if os(macOS)
                MapSnapshotView(coordinates: sampleCoordinates)
                    .opacity(0.2)
                #endif
                
                VStack {
                    // Current tab content
                    if selectedTabIndex == 0 {
                        // Recent Files tab
                        RecentFilesTab(recentFiles: recentFilesManager.recentFiles) { index in
                            openRecentFile(at: index)
                        }
                    } else {
                        // Learn tab
                        LearnTab()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [UTType.gpx, UTType.xml],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                openFile(url: url)
            case .failure(let error):
                print("Error importing file: \(error)")
            }
        }
    }
    
    private func openRecentFile(at index: Int) {
        guard let url = recentFilesManager.resolveRecentFileURL(at: index) else {
            print("Could not resolve recent file URL")
            return
        }
        
        openFile(url: url)
    }
    
    private func openFile(url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        // On iOS, we would handle this through the app's document system
        recentFilesManager.addRecentFile(url, title: url.lastPathComponent)
        #endif
    }
}

// Tab bar for switching between view modes
struct TabBar: View {
    @Binding var selectedIndex: Int
    
    var body: some View {
        HStack(spacing: 0) {
            TabButton(
                title: "Recent",
                isSelected: selectedIndex == 0,
                action: { selectedIndex = 0 }
            )
            
            TabButton(
                title: "Learn",
                isSelected: selectedIndex == 1,
                action: { selectedIndex = 1 }
            )
        }
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}

// Individual tab button
struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color(.selectedControlColor) : Color.clear)
        .cornerRadius(6)
    }
}

// Action button in the sidebar
struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 180)
        }
        .buttonStyle(.plain)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}

// Recent files tab content
struct RecentFilesTab: View {
    let recentFiles: [RecentFile]
    let onOpen: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent GPX Files")
                .font(.headline)
                .padding(.bottom, 10)
            
            if recentFiles.isEmpty {
                VStack {
                    Spacer()
                    Text("No Recent Files")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Open a GPX file to start tracking")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 16)], spacing: 16) {
                        ForEach(recentFiles.indices, id: \.self) { index in
                            RecentFileCard(file: recentFiles[index]) {
                                onOpen(index)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
    }
}

// Card for each recent file
struct RecentFileCard: View {
    let file: RecentFile
    let onOpen: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(file.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        
                        Text(formattedDate(file.dateOpened))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "map")
                        .foregroundColor(.blue)
                }
                
                Text(file.url.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color(.controlBackgroundColor).opacity(0.8) : Color(.controlBackgroundColor).opacity(0.4))
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Learn tab content
struct LearnTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Learn GPXExplore")
                .font(.headline)
                .padding(.bottom, 10)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LearnCard(
                        title: "Visualize GPX Tracks",
                        description: "See your tracks with elevation data on beautiful maps",
                        icon: "map"
                    )
                    
                    LearnCard(
                        title: "Analyze Elevation",
                        description: "View elevation profiles for your tracks and analyze terrain",
                        icon: "mountain.2"
                    )
                    
                    LearnCard(
                        title: "Show Track Details",
                        description: "Get distance, duration, elevation gain and more",
                        icon: "info.circle"
                    )
                    
                    LearnCard(
                        title: "Support for Waypoints",
                        description: "View waypoints and points of interest",
                        icon: "mappin"
                    )
                }
                .padding(8)
            }
        }
    }
}

// Card for each learning item
struct LearnCard: View {
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(.blue)
                .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor).opacity(0.4))
        )
    }
}

// MapSnapshot view to show a static map in the background
struct MapSnapshotView: View {
    let coordinates: [CLLocationCoordinate2D]
    
    var body: some View {
        GeometryReader { geometry in
            MapSnapshotRepresentable(
                coordinates: coordinates,
                size: geometry.size
            )
        }
    }
}

// SwiftUI wrapper for map snapshot
struct MapSnapshotRepresentable: NSViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let size: CGSize
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        createSnapshot(in: view)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        createSnapshot(in: nsView)
    }
    
    private func createSnapshot(in view: NSView) {
        // Create a map region from the coordinates
        let region = coordinateRegion()
        
        // Set up the snapshot options
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.mapType = .standard
        options.showsBuildings = true
        
        // Create the snapshotter
        let snapshotter = MKMapSnapshotter(options: options)
        
        // Take the snapshot
        snapshotter.start { snapshot, error in
            guard let snapshot = snapshot, error == nil else {
                print("Error taking map snapshot: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            // Create an NSImage from the snapshot
            let image = snapshot.image
            
            // Create the image view
            let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
            imageView.image = image
            
            // Remove existing subviews and add the new image view
            view.subviews.forEach { $0.removeFromSuperview() }
            view.addSubview(imageView)
        }
    }
    
    private func coordinateRegion() -> MKCoordinateRegion {
        // Calculate the center and span from the coordinates
        guard !coordinates.isEmpty else {
            // Default to San Francisco if no coordinates
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
        
        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }
        
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5,
            longitudeDelta: (maxLon - minLon) * 1.5
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
}

#Preview {
    WelcomeView()
        .environmentObject(RecentFilesManager())
}

#Preview {
    WelcomeView()
        .environmentObject(RecentFilesManager())
}