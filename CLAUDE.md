# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands
- Build: `xcodebuild -project GPXExplore.xcodeproj -scheme GPXExplore build`
- Run: `xcodebuild -project GPXExplore.xcodeproj -scheme GPXExplore run`
- Clean: `xcodebuild -project GPXExplore.xcodeproj -scheme GPXExplore clean`

## App Functionality
- GPXExplore is a cross-platform macOS/iOS app for viewing GPX track files on a map with elevation data
- Key features: gradient-colored tracks based on elevation changes, display of track statistics
- Core components:
  - `GPXParser`: Parses GPX files into route segments and locations
  - `MapView`: SwiftUI view with platform-specific MapKit integration
  - `SettingsModel`: Manages user preferences for map style and units
  - `ElevationPolyline`: Custom MKPolyline subclass for visualizing elevation data

## Code Style Guidelines
- **Imports**: Group imports by framework (SwiftUI, MapKit, etc.) with Foundation first
- **Formatting**: Use 4-space indentation, avoid trailing whitespace
- **Types**: Use Swift's type inference where appropriate, specify types for public APIs
- **Naming**: Follow Apple's API Design Guidelines (camelCase for properties/methods, TitleCase for types)
- **Error Handling**: Use appropriate error handling with do/catch blocks and meaningful error messaging
- **Comments**: Document complex algorithms and non-obvious functionality
- **Architecture**: Follow MVVM pattern with SwiftUI views
- **Access Control**: Restrict access to implementation details with private/fileprivate
- **Extensions**: Prefer extensions to organize functionality by purpose
- **Swift Features**: Use modern Swift features like optionals, guard statements, and extensions effectively
- **Environment Handling**: Use `#if` conditional compilation for platform-specific code