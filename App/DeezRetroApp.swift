//
//  DeezRetroApp.swift
//  Deez Retro
//
//  Phase 1 host application shell.
//
//  Deliberately minimal: the brief says "No elaborate UI until the emulator
//  engines are proven functional." This app exists to (a) prove the SwiftUI ->
//  Objective-C++ -> Flycast linkage compiles and runs on device, (b) surface the
//  JIT acquisition state, and (c) host a single test ROM for bring-up.
//

import SwiftUI

@main
struct DeezRetroApp: App {
    /// JIT must be resolved before the engine is asked to run.
    /// On iOS 26+ M-series devices this can require an external helper app.
    @StateObject private var jit = JITCoordinator()

    var body: some Scene {
        WindowGroup {
            BringUpView()
                .environmentObject(jit)
                .task {
                    // Attempt acquisition once, at launch. Never auto-launch a
                    // game before this has settled - see docs/BLOCKERS.md B-2.
                    await jit.acquireIfPossible()
                }
        }
    }
}
