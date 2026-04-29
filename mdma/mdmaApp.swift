import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case dark   = "Dark"
    case light  = "Light"
}

@main
struct mdmaApp: App {
    @StateObject private var fs           = FileSystemManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fs)
                .environmentObject(themeManager)
                .frame(minWidth: 820, minHeight: 520)
                .preferredColorScheme(colorScheme)
                .onAppear { applyAppearance() }
                .onChange(of: appearanceMode) { applyAppearance() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note")   { NotificationCenter.default.post(name: .newNote,   object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Folder") { NotificationCenter.default.post(name: .newFolder, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Button("Toggle Focus") { NotificationCenter.default.post(name: .toggleFocus, object: nil) }
                    .keyboardShortcut("e", modifiers: .command)
                Button("Insert File Reference…") { NotificationCenter.default.post(name: .insertFileRef, object: nil) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appSettings) {
                Button("Change Root Folder…") { FileSystemManager.shared.pickRootFolder() }
            }
        }
        
        WindowGroup("Note", id: "detached", for: DetachedTabPayload.self) { $payload in
                    if let p = payload {
                        DetachedWindowView(payload: p)
                            .environmentObject(fs)
                            .environmentObject(themeManager)
                    }
                }
        .windowStyle(.hiddenTitleBar)
                .defaultSize(width: 820, height: 600)


        Settings {
            PreferencesView()
        }
    }

    private var colorScheme: ColorScheme? {
        switch AppearanceMode(rawValue: appearanceMode) {
        case .dark:   return .dark
        case .light:  return .light
        default:      return nil
        }
    }

    private func applyAppearance() {
        switch AppearanceMode(rawValue: appearanceMode) {
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            NSApp.appearance = nil  // follows system
        }
    }
}
