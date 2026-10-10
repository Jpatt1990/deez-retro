//
//  GameLibrary.swift
//  Deez Retro
//
//  Local game import and discovery.
//
//  Phase 2 deliberately does not build a real library UI. What it needs is the
//  minimum that lets someone get a Dreamcast image onto the iPad and boot it,
//  because "Dreamcast software boots" is the third build priority.
//
//  Flycast discovers content through config::ContentPath, which the bridge sets
//  to this app's Documents directory during bring-up. So the whole job here is:
//  put files in Documents, then list them.
//
//  Accepted containers come from Flycast's own exported UTI
//  (shell/apple/emulator-ios/plist.in:121-128): chd, gdi, cue, cdi. Plus .elf,
//  which Flycast loads for homebrew.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A game image sitting in the app's Documents directory.
struct GameFile: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }

    /// Size in bytes, or nil if it could not be read.
    var sizeBytes: Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
    }

    var displaySize: String {
        guard let bytes = sizeBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

@MainActor
final class GameLibrary: ObservableObject {

    /// Extensions Flycast can open. Kept in sync with the exported UTI.
    static let acceptedExtensions: Set<String> = ["chd", "gdi", "cue", "cdi", "elf"]

    /// UTTypes offered to the document picker.
    static var importableTypes: [UTType] {
        var types: [UTType] = []
        for ext in acceptedExtensions.sorted() {
            if let t = UTType(filenameExtension: ext) {
                types.append(t)
            }
        }
        // Always allow "any data" so an unusual container is not blocked outright;
        // Flycast will reject what it cannot parse.
        types.append(.data)
        return types
    }

    @Published private(set) var games: [GameFile] = []
    @Published var lastError: String?

    var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() { refresh() }

    /// Rescans Documents. Cheap enough to call on every appearance.
    func refresh() {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: documentsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles])) ?? []

        games = entries
            .filter { Self.acceptedExtensions.contains($0.pathExtension.lowercased()) }
            .map { GameFile(url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Copies an imported file into Documents, replacing any existing file of the
    /// same name. Handles the security-scoped access the picker requires.
    func importFile(at source: URL) {
        let needsScope = source.startAccessingSecurityScopedResource()
        defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

        let dest = documentsDirectory.appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default

        // A .gdi or .cue refers to sibling track files; copying just the index is
        // not enough. Surface that rather than silently producing a broken entry.
        let ext = source.pathExtension.lowercased()
        if ext == "gdi" || ext == "cue" {
            lastError = "Copied \(source.lastPathComponent), but .\(ext) files reference "
                      + "sibling track files (e.g. .bin/.raw). Import those too, or use "
                      + "a single-file .chd or .cdi image."
        } else {
            lastError = nil
        }

        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
        } catch {
            lastError = "Import failed: \(error.localizedDescription)"
        }
        refresh()
    }

    func delete(_ game: GameFile) {
        do { try FileManager.default.removeItem(at: game.url) }
        catch { lastError = "Delete failed: \(error.localizedDescription)" }
        refresh()
    }
}

/// Thin wrapper over UIDocumentPickerViewController for importing game images.
struct GameImporter: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: GameLibrary.importableTypes,
            asCopy: true)   // asCopy gives us a readable temp URL we can copy in.
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            urls.forEach(onPick)
        }
    }
}
