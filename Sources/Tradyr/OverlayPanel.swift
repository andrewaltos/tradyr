import AppKit
import SwiftUI

/// The always-on-top caption window.
///
/// Non-activating, so it never steals focus from the call or video underneath. It is fully opaque to
/// the mouse (nothing passes through), draggable by its background, and resizable from its edges
/// and from the grip in the bottom-right corner.
final class OverlayPanel: NSPanel {
    @MainActor
    init(model: AppModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 320),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false)

        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        minSize = NSSize(width: 420, height: 160)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = FirstMouseHostingView(rootView: OverlayView(model: model))
        // Let the window be resized freely instead of tracking the SwiftUI content's ideal size.
        host.sizingOptions = []
        contentView = host
        positionAtBottomCenter()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.minY + 40))
    }
}

/// A hosting view that handles the first click even though its window isn't key,
/// so buttons work without first having to focus the overlay.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Bottom-right resize handle. Resizes with the top-left corner pinned, using screen-space mouse
/// positions so the window moving under the cursor can't feed back into the drag.
struct ResizeGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { GripView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class GripView: NSView {
        private var startMouse = NSPoint.zero
        private var startFrame = NSRect.zero

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.withAlphaComponent(0.45).setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            for offset in stride(from: CGFloat(5), through: 13, by: 4) {
                path.move(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + offset))
                path.line(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 2))
            }
            path.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            startMouse = NSEvent.mouseLocation
            startFrame = window.frame
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let mouse = NSEvent.mouseLocation
            var frame = startFrame
            let width = max(window.minSize.width, startFrame.width + (mouse.x - startMouse.x))
            let height = max(window.minSize.height, startFrame.height - (mouse.y - startMouse.y))
            frame.size = NSSize(width: width, height: height)
            frame.origin.y = startFrame.maxY - height
            window.setFrame(frame, display: true)
        }
    }
}
