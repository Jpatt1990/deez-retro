//
//  BringUpView.swift
//  Deez Retro
//
//  The Phase 2 harness.
//
//  This is deliberately NOT a product interface. The brief says not to spend
//  time on the final interface, and Phase 2 has four build priorities:
//     1. ARM64 compilation
//     2. app launches on the iPad
//     3. Dreamcast software boots
//     4. performance measured on the M4
//  So this screen exists to make those four things observable and no more:
//  engine state, CPU execution mode, renderer, live FPS, and a way to get a
//  game onto the device and boot it.
//

import SwiftUI

struct BringUpView: View {
    @StateObject private var core = CoreViewModel()
    @StateObject private var library = GameLibrary()
    @State private var showingImporter = false
    @State private var launched: GameFile?

    var body: some View {
        NavigationStack {
            List {
                engineSection
                librarySection
                honestySection
            }
            .navigationTitle("Deez Retro — Dreamcast")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingImporter) {
                GameImporter { url in
                    library.importFile(at: url)
                }
            }
            .fullScreenCover(item: $launched) { game in
                EmulatorScreen(game: game, core: core)
            }
            .onAppear { library.refresh(); core.refresh() }
        }
    }

    // MARK: - Engine status

    private var engineSection: some View {
        Section("Engine status") {
            statusRow("Engine", "Dreamcast (Flycast)")

            statusRow("Core linked", core.status.engineLinked ? "yes" : "no",
                      ok: core.status.engineLinked)

            statusRow("State", core.stateLabel,
                      ok: core.status.state == .running || core.status.state == .idle)

            statusRow("CPU mode", core.status.executionModeLabel,
                      ok: core.status.executionMode != .unavailable)

            if core.status.builtWithoutRecompiler {
                Label("Built interpreter-only (TARGET_NO_REC). No JIT and no "
                      + "entitlements required — this is the only configuration "
                      + "that can ship on the App Store.",
                      systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(core.status.executionModeDetail)
                .font(.footnote)
                .foregroundStyle(.secondary)

            statusRow("Renderer", core.status.rendererName)
            statusRow("FPS", String(format: "%.1f", core.measuredFPS))

            if let error = core.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        Section {
            if library.games.isEmpty {
                Text("No games yet. Import a .chd, .cdi, .gdi or .cue image, or a "
                     + "homebrew .elf. Files can also be dropped into the app's "
                     + "Documents folder over Finder or the Files app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(library.games) { game in
                    Button {
                        core.prepare(for: game)
                        launched = game
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.name).font(.body)
                                Text(game.displaySize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle")
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { library.delete(game) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if let error = library.lastError {
                Text(error).font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Library")
        } footer: {
            Text("Flycast resolves content through config::ContentPath, which the "
                 + "bridge points at this app's Documents directory.")
        }
    }

    // MARK: - Honesty

    private var honestySection: some View {
        Section {
            Text("This is a bring-up harness, not a product UI. Nothing here "
                 + "claims the emulator works: a build counts as working only "
                 + "once it has compiled, run and been benchmarked on the "
                 + "physical M4 iPad. See docs/PHASE2-BUILD-REPORT.md.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func statusRow(_ label: String, _ value: String, ok: Bool? = nil) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .monospaced()
                .foregroundStyle(ok == false ? Color.red : Color.secondary)
        }
    }
}

// MARK: - Full-screen emulator

/// Hosts the GL view and owns the engine lifecycle for one game.
private struct EmulatorScreen: View {
    let game: GameFile
    @ObservedObject var core: CoreViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            EmulatorHostView(
                isRunning: core.isRunning,
                // The GL context must exist before the engine is initialised,
                // so bring-up is triggered from here rather than in onAppear.
                onReady: {
                    core.bringUpAndLaunch(game)
                }
            )
            .ignoresSafeArea()

            // Minimal status overlay. Tap to hide is intentionally not built yet.
            VStack(alignment: .leading, spacing: 4) {
                Text(core.status.executionModeLabel).bold()
                Text(String(format: "%.1f fps", core.measuredFPS))
                Text(core.stateLabel)
            }
            .font(.caption)
            .monospaced()
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        core.shutdown()
                        dismiss()
                    } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                Spacer()
            }

            if let error = core.lastError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.footnote)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
        }
        .statusBarHidden()
    }
}

// MARK: - Core view model

@MainActor
final class CoreViewModel: ObservableObject {

    struct StatusView {
        var engineLinked = false
        var state: DREngineState = .notLinked
        var executionMode: DRExecutionMode = .unknown
        var executionModeDetail = ""
        var rendererName = "none"
        var builtWithoutRecompiler = false

        var executionModeLabel: String {
            switch executionMode {
            case .dynarec:     return "dynarec (JIT)"
            case .interpreter: return "interpreter (no JIT)"
            case .unavailable: return "unavailable"
            default:           return "unknown"
            }
        }
    }

    @Published var status = StatusView()
    @Published var measuredFPS: Double = 0
    @Published var isRunning = false
    @Published var lastError: String?

    private var pending: GameFile?
    private var pollTask: Task<Void, Never>?

    init() {
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.refresh()
            }
        }
    }

    deinit { pollTask?.cancel() }

    var stateLabel: String {
        switch status.state {
        case .notLinked: return "not linked"
        case .idle:      return "idle"
        case .running:   return "running"
        case .paused:    return "paused"
        case .failed:    return "failed"
        default:         return "unknown"
        }
    }

    func refresh() {
        let s = DRCore.shared().status(for: .dreamcast)
        status = StatusView(
            engineLinked: s.engineLinked,
            state: s.state,
            executionMode: s.executionMode,
            executionModeDetail: s.executionModeDetail,
            rendererName: s.rendererName,
            builtWithoutRecompiler: s.builtWithoutRecompiler
        )
        measuredFPS = DRCore.shared().measuredFPS
    }

    func prepare(for game: GameFile) {
        pending = game
        lastError = nil
    }

    /// Runs after the GL context exists. Order matters and mirrors
    /// docs/PHASE2-IOS-INTEGRATION.md §3.
    func bringUpAndLaunch(_ game: GameFile) {
        guard !isRunning else { return }
        lastError = nil

        do {
            try DRCore.shared().startEngine(.dreamcast)
        } catch {
            lastError = "Engine bring-up failed: \(error.localizedDescription)"
            return
        }

        do {
            try DRCore.shared().loadGame(atPath: game.url.path)
        } catch {
            lastError = "Load failed: \(error.localizedDescription)"
            return
        }

        DRCore.shared().start()
        isRunning = true
        refresh()
    }

    func shutdown() {
        DRCore.shared().shutdown()
        isRunning = false
        pending = nil
        refresh()
    }
}
