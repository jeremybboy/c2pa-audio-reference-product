import AppKit
import SwiftUI

@main
struct LoopGeneratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1450, height: 900)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var viewModel: AppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let visibleWindows = NSApp.windows.filter(\.isVisible)
            if visibleWindows.isEmpty {
                createFallbackWindow()
            } else {
                visibleWindows.first?.makeKeyAndOrderFront(nil)
                captureWindowIfRequested(visibleWindows.first)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func createFallbackWindow() {
        let viewModel = AppViewModel()
        let rootView = ContentView(viewModel: viewModel)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1450, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Loop Generator"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 1180, height: 760)
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.viewModel = viewModel
        self.window = window
        NSLog("Loop Generator main window created: %@", NSStringFromRect(window.frame))
        captureWindowIfRequested(window)
    }

    private func captureWindowIfRequested(_ window: NSWindow?) {
        guard let destination = ProcessInfo.processInfo.environment["LOOP_GENERATOR_CAPTURE_PATH"],
              let window else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard let view = window.contentView,
                  let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                return
            }
            view.cacheDisplay(in: view.bounds, to: representation)
            guard let png = representation.representation(using: .png, properties: [:]) else {
                return
            }
            do {
                try png.write(to: URL(fileURLWithPath: destination), options: .atomic)
                NSLog("Loop Generator UI capture written to %@", destination)
            } catch {
                NSLog("Loop Generator UI capture failed: %@", error.localizedDescription)
            }
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.minSize = NSSize(width: 1180, height: 760)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
