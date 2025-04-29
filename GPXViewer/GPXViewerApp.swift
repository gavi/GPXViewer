//
//  GPXViewerApp.swift
//  GPXViewer
//
//  Created by Gavi Narra on 4/29/25.
//

import SwiftUI

@main
struct GPXViewerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: GPXViewerDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
