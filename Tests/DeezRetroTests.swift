//
//  DeezRetroTests.swift
//  Deez Retro
//
//  Phase 1 smoke tests. These run on the iOS *simulator*, which is important to
//  understand: the simulator cannot exercise the dynarec at all (Flycast forces
//  TARGET_NO_REC there — core/build.h:41-44), so anything measured or asserted
//  here says nothing about M4 performance. These tests check plumbing only.
//

import XCTest
@testable import DeezRetro

final class DeezRetroTests: XCTestCase {

    /// The facade must be usable before any engine exists, and must not claim an
    /// engine is linked when it is not. This is the test that stops the project
    /// from ever displaying a fake success.
    func testStatusIsHonestWhenNoEngineIsLinked() {
        let status = DRCore.shared().status(for: .dreamcast)

        if !status.engineLinked {
            XCTAssertEqual(status.executionMode, .unavailable,
                           "An unlinked engine must report .unavailable, not a mode.")
            XCTAssertFalse(status.executionModeDetail.isEmpty,
                           "The reason an engine is unavailable must be surfaced.")
        }
    }

    /// PS2 is explicitly out of scope for Phase 1. It must never report as linked.
    func testPS2IsNotReportedAsIntegrated() {
        let status = DRCore.shared().status(for: .ps2)
        XCTAssertFalse(status.engineLinked,
                       "No PS2 engine is integrated in Phase 1 — see PHASE1-FEASIBILITY.md §7.")
        XCTAssertEqual(status.executionMode, .unavailable)
    }

    /// The PS2 path must fail loudly rather than silently doing nothing.
    func testStartingPS2EngineFails() {
        XCTAssertThrowsError(try DRCore.shared().startEngine(.ps2)) { error in
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    /// The JIT coordinator must never report readiness without evidence.
    /// On a simulator or an unsigned build there is no CS_DEBUGGED and no
    /// allow-jit entitlement, so it must not claim to be ready.
    func testJITIsNotClaimedWithoutEntitlement() {
        XCTAssertFalse(JITCoordinator.hasEntitlement("com.apple.developer.kernel.allow-jit"),
                       "A test build cannot hold com.apple.developer.kernel.allow-jit.")
    }

    /// The StikDebug URL must always carry bundle id and pid, and must send a
    /// script name ONLY where TXM/SPTM is present — sending it where it is absent
    /// is explicitly wrong per the StikJIT integration protocol.
    func testStikDebugURLIncludesScriptOnlyWhenTXMPresent() {
        let withTXM = JITCoordinator.stikDebugURL(bundleID: "com.deezretro.app",
                                                  pid: 4242,
                                                  script: "universal.js")
        XCTAssertEqual(withTXM?.scheme, "stikdebug")
        XCTAssertEqual(withTXM?.host, "enable-jit")
        XCTAssertTrue(withTXM?.query?.contains("bundle-id=com.deezretro.app") ?? false)
        XCTAssertTrue(withTXM?.query?.contains("pid=4242") ?? false)
        XCTAssertTrue(withTXM?.query?.contains("script-name=universal.js") ?? false)

        let withoutTXM = JITCoordinator.stikDebugURL(bundleID: "com.deezretro.app",
                                                     pid: 4242,
                                                     script: nil)
        XCTAssertFalse(withoutTXM?.query?.contains("script-name") ?? true,
                       "script-name must be omitted when TXM/SPTM is absent.")
    }

    /// The bridge must report measured FPS as 0 when nothing is running, rather
    /// than returning an uninitialised or stale value.
    func testFPSIsZeroWhenIdle() {
        XCTAssertEqual(DRCore.shared().measuredFPS, 0, accuracy: 0.0001)
    }
}
