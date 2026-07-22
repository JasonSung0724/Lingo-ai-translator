import SwiftUI

struct QuickPopupView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 360, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12)))
    }
}

final class QuickPopup {
    static let shared = QuickPopup()
    private var panel: NSPanel?
    private var monitor: Any?
    private var token = 0

    func show(text: String, at point: NSPoint) {
        close()
        let host = NSHostingView(rootView: QuickPopupView(text: text))
        let size = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.contentView = host

        let screen = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: point.x, y: point.y - size.height - 10)
        if origin.x + size.width > screen.maxX { origin.x = screen.maxX - size.width - 6 }
        if origin.x < screen.minX { origin.x = screen.minX + 6 }
        if origin.y < screen.minY { origin.y = point.y + 16 }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        self.panel = panel

        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) {
            [weak self] _ in self?.close()
        }
        // Token guard: an older popup's auto-close must not dismiss a newer one.
        token += 1
        let current = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.token == current else { return }
            self.close()
        }
    }

    // Streaming updates: swap the text in place, keeping the TOP-LEFT corner
    // fixed so the popup grows downward instead of jumping around. A dismissed
    // popup stays dismissed — updates never resurrect it.
    func update(text: String) {
        guard let panel, let host = panel.contentView as? NSHostingView<QuickPopupView> else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        host.rootView = QuickPopupView(text: text)
        let size = host.fittingSize
        panel.setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height,
                              width: size.width, height: size.height), display: true)
    }

    // Auto-dismiss a short confirmation ("✓ Replaced") without cutting off a
    // popup that was re-shown for something newer in the meantime.
    func closeSoon(after delay: TimeInterval = 1.2) {
        let current = token
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.token == current else { return }
            self.close()
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
