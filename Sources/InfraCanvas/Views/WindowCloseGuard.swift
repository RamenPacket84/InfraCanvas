import AppKit
import SwiftUI

struct WindowCloseGuard: NSViewRepresentable {
    var shouldClose: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(shouldClose: shouldClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        attachDelegate(from: view, context: context)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.shouldClose = shouldClose
        attachDelegate(from: view, context: context)
    }

    private func attachDelegate(from view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if window.delegate !== context.coordinator {
                window.delegate = context.coordinator
            }
        }
    }
}

extension WindowCloseGuard {
    final class Coordinator: NSObject, NSWindowDelegate {
        var shouldClose: () -> Bool

        init(shouldClose: @escaping () -> Bool) {
            self.shouldClose = shouldClose
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            shouldClose()
        }
    }
}
