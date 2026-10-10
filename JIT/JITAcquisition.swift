//
//  JITAcquisition.swift
//  Deez Retro
//
//  iPadOS JIT acquisition and readiness, for the M4 iPad Pro.
//
//  WHY THIS FILE EXISTS
//  --------------------
//  iPadOS does not let a normal, sandboxed third-party app map writable memory
//  as executable. Every ARM64 dynarec in scope for Deez Retro (Flycast's SH4
//  recompiler, Play!'s EE/VU JIT, PCSX2's recompilers) needs exactly that.
//  Without JIT the only correct fallback is a CPU interpreter, which is
//  dramatically slower.
//
//  On top of the classic restriction, iOS 26 introduced TXM/SPTM on M-series
//  hardware (this includes M4 iPad Pro): a plain debugger attach is no longer
//  sufficient, because each executable region must be *prepared* through the
//  debug connection using a breakpoint protocol before the app executes code
//  from it. See docs/BLOCKERS.md B-1 and B-2.
//
//  STATUS: UNVERIFIED. This module encodes the documented protocol; it has not
//  been run on a physical iPad. Treat every path here as a hypothesis to be
//  validated during Phase 1 bring-up, not as working code.
//
//  DISTRIBUTION CONSTRAINT
//  -----------------------
//  com.apple.developer.kernel.allow-jit (the iOS 26 native JIT entitlement) is
//  NOT permitted in App Store submissions. An App Store build therefore always
//  needs an external helper (StikDebug / StikJIT / AltJIT / JitStreamer) plus
//  get-task-allow, Developer Mode, a pairing file and a mounted DDI. This is a
//  product-level constraint, not a coding problem.
//

import Foundation
import UIKit
import Darwin

@_silgen_name("csops")
private func csops(_ pid: pid_t, _ ops: UInt32, _ useraddr: UnsafeMutableRawPointer, _ usersize: Int) -> Int32

private let CS_OPS_STATUS: UInt32 = 0
private let CS_DEBUGGED: Int32 = 0x1000_0000

/// How the app is allowed to obtain JIT, in the order we try them.
enum JITMethod: String, CaseIterable, Identifiable {
    case stikDebug      = "StikDebug"
    case waitForDebugger = "Wait for Debugger"
    case none           = "None"

    var id: String { rawValue }
}

@MainActor
final class JITCoordinator: ObservableObject {

    enum State: Equatable, CustomStringConvertible {
        case unknown
        case acquiring(method: JITMethod)
        case ready(source: String)
        case unavailable(reason: String)

        var isReady: Bool { if case .ready = self { return true }; return false }

        var description: String {
            switch self {
            case .unknown:                 return "unknown"
            case .acquiring(let method):   return "acquiring via \(method.rawValue)…"
            case .ready(let source):       return "ready (\(source))"
            case .unavailable(let reason): return "unavailable — \(reason)"
            }
        }
    }

    @Published private(set) var state: State = .unknown

    /// TXM/SPTM present means the breakpoint protocol is mandatory, not optional.
    @Published private(set) var txmPresent: Bool = false

    /// Whether this binary carries get-task-allow. Without it, no JIT path works.
    @Published private(set) var hasGetTaskAllow: Bool = false

    /// The single developer-configured script this app's allocator implements.
    /// Must not become a user-facing setting.
    private let scriptName = "universal.js"

    private let stikDebugScheme = "stikdebug"

    // MARK: - Capability probes

    /// True when the running process is already permitted to execute
    /// unvalidated pages. On iOS 18.4+ the old ptrace self-attach trick no
    /// longer sets this for sideloaded apps, so we cannot rely on it alone.
    static func isDebugged() -> Bool {
        var flags: Int32 = 0
        let rv = withUnsafeMutablePointer(to: &flags) {
            csops(getpid(), CS_OPS_STATUS, $0, MemoryLayout<Int32>.size)
        }
        return rv == 0 && (flags & CS_DEBUGGED) != 0
    }

    /// Reads a Boolean entitlement from our own code signature.
    /// Uses Security framework SPI; not App Store safe.
    static func hasEntitlement(_ name: String) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        defer { CFRelease(task) }
        guard let value = SecTaskCopyValueForEntitlement(task, name as CFString, nil) else {
            return false
        }
        defer { CFRelease(value) }
        return (value as? Bool) == true
    }

    /// TXM presence is detected by the runtime class that mediates it.
    static func detectTXM() -> Bool {
        NSClassFromString("JITAuthorizer") != nil
    }

    // MARK: - Acquisition

    func acquireIfPossible() async {
        hasGetTaskAllow = Self.hasEntitlement("get-task-allow")
        txmPresent = Self.detectTXM()

        // 1. Already good? (jailbroken / debugger already attached / TrollStore)
        if Self.isDebugged() {
            state = .ready(source: "CS_DEBUGGED already set")
            DRCoreNotifyJITAcquired()
            return
        }

        // 2. Native iOS 26 entitlement. Only present on JB / sideloaded builds.
        if Self.hasEntitlement("com.apple.developer.kernel.allow-jit") {
            state = .ready(source: "com.apple.developer.kernel.allow-jit")
            DRCoreNotifyJITAcquired()
            return
        }

        // 3. We need an external helper. Refuse to pretend otherwise.
        guard hasGetTaskAllow else {
            state = .unavailable(
                reason: "This build lacks get-task-allow, so no JIT path can work. "
                      + "Reinstall with a signing method that preserves it.")
            return
        }

        await requestJITFromStikDebug()
    }

    /// Hands off to StikDebug via URL scheme. Opening the URL only means iOS
    /// accepted the request - it does NOT mean JIT was acquired. We must wait
    /// for readiness to appear on our own process.
    private func requestJITFromStikDebug() async {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            state = .unavailable(reason: "No bundle identifier.")
            return
        }
        guard let url = Self.stikDebugURL(bundleID: bundleID,
                                          pid: getpid(),
                                          script: txmPresent ? scriptName : nil) else {
            state = .unavailable(reason: "Could not build the StikDebug request URL.")
            return
        }

        state = .acquiring(method: .stikDebug)
        let opened = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
        guard opened else {
            state = .unavailable(
                reason: "StikDebug is not installed or refused the request. "
                      + "Install StikDebug and retry, or use Wait for Debugger.")
            return
        }

        // Poll our own CS_DEBUGGED bit. Never trust the URL open alone.
        let ready = await waitForDebugged(timeout: 60)
        if ready {
            state = .ready(source: "StikDebug")
            DRCoreNotifyJITAcquired()
        } else {
            state = .unavailable(
                reason: "Timed out waiting for JIT. Ensure Developer Mode is on, "
                      + "a pairing file is available, and the Developer Disk Image is mounted.")
        }
    }

    static func stikDebugURL(bundleID: String, pid: pid_t, script: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "stikdebug"
        components.host = "enable-jit"
        var items = [
            URLQueryItem(name: "bundle-id", value: bundleID),
            URLQueryItem(name: "pid", value: String(pid)),
        ]
        // Only send the script when TXM/SPTM is present. Where it is absent, a
        // debugger attach alone is enough and the parameter must be omitted.
        if let script { items.append(URLQueryItem(name: "script-name", value: script)) }
        components.queryItems = items
        return components.url
    }

    private func waitForDebugged(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Self.isDebugged() { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return false }
        }
        return false
    }
}

// MARK: - Security framework SPI
//
// Declared here rather than imported so this file does not need a Security.framework
// link dependency at the Swift layer; link Security.framework in the app target.
@_silgen_name("SecTaskCreateFromSelf")
private func SecTaskCreateFromSelf(_ allocator: CFAllocator?) -> CFTypeRef?

@_silgen_name("SecTaskCopyValueForEntitlement")
private func SecTaskCopyValueForEntitlement(_ task: CFTypeRef,
                                            _ entitlement: CFString,
                                            _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFTypeRef?
