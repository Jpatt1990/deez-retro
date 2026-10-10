//
//  EmulatorHostView.swift
//  Deez Retro
//
//  The one place where SwiftUI meets OpenGL ES.
//
//  Flycast's iOS renderer is OpenGL ES 3 and is presented through a GLKView.
//  There is no Metal renderer in Flycast (its renderers are dx9/dx11/gl4/gles/
//  norender/vulkan - there is no `metal` directory), so this is not a stylistic
//  choice.
//
//  HOW THE FRAME LOOP WORKS
//  ------------------------
//  Flycast's frame pump is mainui_rend_frame() (core/ui/mainui.cpp:38), which
//  internally calls os_DoEvents(), os_UpdateInputState(), the ImGui overlay and
//  emu.render(). It must be called once per display refresh.
//
//  Upstream drives it from a GLKViewController's -glkView:drawInRect: with
//  setPreferredFramesPerSecond:60. We keep the same shape but own the loop: a
//  CADisplayLink drives GLKView.display(), and the coordinator implements
//  GLKViewDelegate to call DRCore.renderFrame().
//
//  Presentation is implicit. GLKView presents its own drawable after the draw
//  callback returns, and Flycast's iOS path deliberately does not bind
//  framebuffer 0 (see the `#ifndef TARGET_IPHONE` guard in
//  core/rend/gles/opengl_driver.cpp:58), so it renders into whatever framebuffer
//  GLKit has bound. That is also why OSXGraphicsContext::swap() is effectively a
//  no-op: do_swap_automation() is empty unless TEST_AUTOMATION is defined
//  (core/wsi/gl_context.h:60-62).
//
//  NOT REUSED: Flycast's own `EmulatorView` (a GLKView subclass, 73 lines). It
//  is reusable in principle, but taking it would put
//  `shell/apple/emulator-ios/emulator/` on the Swift bridging-header path and
//  make the app target depend on the engine being checked out even when
//  DEEZRETRO_HAVE_FLYCAST=0. The only thing forgone is its TouchMouse
//  registration; controller input, which is what Phase 2 needs, comes from
//  `ios_gamepad.h` on the bridge side.
//

import SwiftUI
import GLKit
import QuartzCore

struct EmulatorHostView: UIViewRepresentable {

    /// Set true to run. Pausing stops feeding frames but keeps the GL context
    /// and the loaded game.
    var isRunning: Bool

    /// Called once the EAGL context exists and is current.
    ///
    /// Engine bring-up MUST wait for this: `mainui_init()` ->
    /// `rend_init_renderer()` creates the GLES context object and fails if no
    /// EAGL context is current. Triggering bring-up from `onAppear` instead
    /// would race the view's construction.
    var onReady: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GLKView {
        // GLKView takes its context at construction; there is no inherited
        // parameterless initialiser to set it on afterwards.
        let eagl = EAGLContext(api: .openGLES3) ?? EAGLContext(api: .openGLES2)

        guard let eaglContext = eagl else {
            NSLog("[DeezRetro] Could not create an EAGL context; no rendering.")
            context.coordinator.contextFailed = true
            return GLKView(frame: .zero, context: nil)
        }

        let view = GLKView(frame: .zero, context: eaglContext)
        view.delegate = context.coordinator

        // We drive presentation from a CADisplayLink rather than letting GLKit
        // animate the view itself, so the emulator controls frame pacing.
        view.enableSetNeedsDisplay = false
        view.isOpaque = true

        EAGLContext.setCurrent(eaglContext)
        context.coordinator.startDisplayLink(for: view)

        if let onReady {
            // Not during the view-update pass.
            DispatchQueue.main.async { onReady() }
        }
        return view
    }

    func updateUIView(_ view: GLKView, context: Context) {
        context.coordinator.setRunning(isRunning)
    }

    static func dismantleUIView(_ view: GLKView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, GLKViewDelegate {

        private weak var view: GLKView?
        private var displayLink: CADisplayLink?
        private var running = false
        /// True when the EAGL context could not be created. The screen reports
        /// this rather than silently showing a black view.
        private(set) var contextFailed = false

        func startDisplayLink(for view: GLKView) {
            self.view = view
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFramesPerSecond = 60   // Dreamcast native rate
            // Paused until the screen says the game is running.
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
            if let ctx = view?.context, EAGLContext.current() === ctx {
                EAGLContext.setCurrent(nil)
            }
            view = nil
        }

        func setRunning(_ running: Bool) {
            self.running = running
            displayLink?.isPaused = !running
        }

        @objc private func tick() {
            guard running else { return }
            view?.display()   // triggers glkView(_:drawInRect:) below
        }

        // MARK: GLKViewDelegate

        func glkView(_ view: GLKView, drawInRect rect: CGRect) {
            // Must run on the thread that owns the GL context, which is the main
            // thread here. renderFrame() returns false when no frame was
            // produced, which is normal while the engine is coming up.
            _ = DRCore.shared().renderFrame()
        }
    }
}
