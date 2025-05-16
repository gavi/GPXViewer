import Foundation
import SwiftUI
import UniformTypeIdentifiers

class RecentFilesManager: ObservableObject {
    private let maxRecentFiles = 10
    private let recentFilesKey = "GPXExploreRecentFiles"
    
    @Published var recentFiles: [RecentFile] = []
    
    init() {
        loadRecentFiles()
    }
    
    func addRecentFile(_ url: URL, title: String) {
        // Remove duplicates
        recentFiles.removeAll(where: { $0.url == url })
        
        // Create a bookmark for persistent access
        do {
            let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            let newFile = RecentFile(
                url: url,
                title: title,
                bookmarkData: bookmarkData,
                dateOpened: Date()
            )
            
            // Add to the front of the list
            recentFiles.insert(newFile, at: 0)
            
            // Trim the list if needed
            if recentFiles.count > maxRecentFiles {
                recentFiles = Array(recentFiles.prefix(maxRecentFiles))
            }
            
            // Save updated list
            saveRecentFiles()
        } catch {
            print("Error creating bookmark for recent file: \(error)")
        }
    }
    
    func clearRecentFiles() {
        recentFiles.removeAll()
        saveRecentFiles()
    }
    
    func resolveRecentFileURL(at index: Int) -> URL? {
        guard index >= 0 && index < recentFiles.count else { return nil }
        
        let recentFile = recentFiles[index]
        
        // Try to resolve the bookmark
        do {
            var isStale = false
            let resolvedURL = try URL(resolvingBookmarkData: recentFile.bookmarkData, 
                                     options: .withSecurityScope, 
                                     relativeTo: nil, 
                                     bookmarkDataIsStale: &isStale)
            
            if isStale {
                // If the bookmark is stale but we got a URL, update it
                if let updatedBookmark = try? resolvedURL.bookmarkData(options: .minimalBookmark, 
                                                                     includingResourceValuesForKeys: nil, 
                                                                     relativeTo: nil) {
                    recentFiles[index].bookmarkData = updatedBookmark
                    saveRecentFiles()
                }
            }
            
            return resolvedURL
        } catch {
            print("Error resolving bookmark: \(error)")
            
            // Remove invalid bookmark
            recentFiles.remove(at: index)
            saveRecentFiles()
            return nil
        }
    }
    
    private func loadRecentFiles() {
        if let data = UserDefaults.standard.data(forKey: recentFilesKey) {
            do {
                let decoder = JSONDecoder()
                recentFiles = try decoder.decode([RecentFile].self, from: data)
                
                // Remove any files that no longer exist
                recentFiles = recentFiles.filter { recentFile in
                    var isStale = false
                    if let resolvedURL = try? URL(resolvingBookmarkData: recentFile.bookmarkData, 
                                                options: .withSecurityScope, 
                                                relativeTo: nil, 
                                                bookmarkDataIsStale: &isStale) {
                        return FileManager.default.fileExists(atPath: resolvedURL.path)
                    }
                    return false
                }
                
                // Save the filtered list
                saveRecentFiles()
            } catch {
                print("Error loading recent files: \(error)")
                recentFiles = []
            }
        }
    }
    
    private func saveRecentFiles() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(recentFiles)
            UserDefaults.standard.set(data, forKey: recentFilesKey)
        } catch {
            print("Error saving recent files: \(error)")
        }
    }
}

struct RecentFile: Codable, Identifiable, Equatable {
    var id: String { url.absoluteString }
    let url: URL
    let title: String
    var bookmarkData: Data
    let dateOpened: Date
    
    static func == (lhs: RecentFile, rhs: RecentFile) -> Bool {
        return lhs.url == rhs.url
    }
    
    enum CodingKeys: String, CodingKey {
        case url, title, bookmarkData, dateOpened
    }
    
    init(url: URL, title: String, bookmarkData: Data, dateOpened: Date) {
        self.url = url
        self.title = title
        self.bookmarkData = bookmarkData
        self.dateOpened = dateOpened
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let urlString = try container.decode(String.self, forKey: .url)
        guard let url = URL(string: urlString) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: container, debugDescription: "Invalid URL string")
        }
        self.url = url
        self.title = try container.decode(String.self, forKey: .title)
        self.bookmarkData = try container.decode(Data.self, forKey: .bookmarkData)
        self.dateOpened = try container.decode(Date.self, forKey: .dateOpened)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url.absoluteString, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(bookmarkData, forKey: .bookmarkData)
        try container.encode(dateOpened, forKey: .dateOpened)
    }
}