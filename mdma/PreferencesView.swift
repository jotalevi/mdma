import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var fs           = FileSystemManager.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var git          = GitManager.shared
    @AppStorage("appearanceMode")       private var appearanceMode       = "System"
    @AppStorage("showFileExtensions")   private var showFileExtensions   = true
    @AppStorage("autosave")             private var autosave             = true
    @AppStorage("bodyFontName")         private var bodyFontName         = "Georgia"
    @AppStorage("monoFontName")         private var monoFontName         = ""
    @AppStorage("fontSize")             private var fontSize             = 15.0
    @AppStorage("lineHeightMultiplier") private var lineHeightMultiplier = 1.3
    @AppStorage("vimMode")              private var vimMode              = false
    @AppStorage("spellCheck")           private var spellCheck           = false
    @AppStorage("showWordCount")        private var showWordCount        = true
    @AppStorage("ligatures")            private var ligatures            = false
    @AppStorage("gitAutoCommit")        private var gitAutoCommit        = false
    @State private var isMoving = false

    // Font family lists (built once)
    private var bodyFamilies: [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }
    private var monoFamilies: [String] {
        ["System Monospace"] + NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .filter { family in
                guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                      let first   = members.first,
                      let fname   = first[0] as? String,
                      let font    = NSFont(name: fname, size: 12)
                else { return false }
                return font.isFixedPitch
            }
            .sorted()
    }

    private var isInICloud: Bool {
        guard let root = fs.rootURL else { return false }
        let iCloudBase = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Mobile Documents")
        return root.path.hasPrefix(iCloudBase.path)
            || root.path.contains("iCloud~")
            || root.path.contains("com~apple~CloudDocs")
            || root.path.lowercased().contains("icloud")
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color Scheme", selection: $appearanceMode) {
                    Text("System").tag("System")
                    Text("Dark").tag("Dark")
                    Text("Light").tag("Light")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceMode) { applyAppearance() }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme").font(.system(size: 13))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Theme.all, id: \.name) { theme in
                            ThemeSwatchButton(
                                theme: theme,
                                isSelected: themeManager.themeName == theme.name
                            ) {
                                themeManager.themeName = theme.name
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }

            Section("Editor") {
                Toggle("Show File Extensions", isOn: $showFileExtensions)
                    .onChange(of: showFileExtensions) {
                        NotificationCenter.default.post(name: .themeDidChange, object: nil)
                    }

                Toggle("Autosave", isOn: $autosave)
                if !autosave {
                    Text("Files save with ⌘S. Unsaved tabs show a dot indicator.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Toggle("Spell Check", isOn: $spellCheck)
                    .onChange(of: spellCheck) {
                        NotificationCenter.default.post(name: .spellCheckChanged, object: nil)
                    }

                Toggle("Vim Mode", isOn: $vimMode)
                    .onChange(of: vimMode) {
                        NotificationCenter.default.post(name: .vimModeSettingChanged, object: nil)
                    }
                if vimMode {
                    Text("Normal/Insert/Visual modes. i to insert, Esc to Normal, v to Visual, hjkl to navigate.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Toggle("Show Word Count", isOn: $showWordCount)
            }

            Section("Typography") {
                // Body font
                Picker("Body Font", selection: $bodyFontName) {
                    ForEach(bodyFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: bodyFontName) {
                    NotificationCenter.default.post(name: .themeDidChange, object: nil)
                }

                // Mono font
                Picker("Mono Font", selection: $monoFontName) {
                    ForEach(monoFamilies, id: \.self) { family in
                        Text(family).tag(family == "System Monospace" ? "" : family)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: monoFontName) {
                    NotificationCenter.default.post(name: .themeDidChange, object: nil)
                }

                // Font size
                HStack(spacing: 10) {
                    Text("Font Size")
                        .frame(width: 90, alignment: .leading)
                    Slider(value: $fontSize, in: 10...30, step: 1)
                        .onChange(of: fontSize) {
                            NotificationCenter.default.post(name: .themeDidChange, object: nil)
                        }
                    Text("\(Int(fontSize)) pt")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 42, alignment: .trailing)
                }

                // Line height
                HStack(spacing: 10) {
                    Text("Line Height")
                        .frame(width: 90, alignment: .leading)
                    Slider(value: $lineHeightMultiplier, in: 1.0...2.0, step: 0.05)
                        .onChange(of: lineHeightMultiplier) {
                            NotificationCenter.default.post(name: .themeDidChange, object: nil)
                        }
                    Text(String(format: "%.2f×", lineHeightMultiplier))
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 42, alignment: .trailing)
                }

                Toggle("Ligatures", isOn: $ligatures)
                    .onChange(of: ligatures) {
                        NotificationCenter.default.post(name: .themeDidChange, object: nil)
                    }
            }

            Section("Root Folder") {
                if let url = fs.rootURL {
                    LabeledContent("Location") {
                        Text(url.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack {
                        Button("Change Folder…") { pick() }
                        Spacer()
                        Button("Clear", role: .destructive) { fs.clearRoot() }
                    }
                } else {
                    Text("No folder selected").foregroundColor(.secondary)
                    Button("Choose Folder…") { pick() }
                }
            }

            if fs.rootURL != nil {
                if isInICloud {
                    Section("iCloud Sync") {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.icloud")
                                .foregroundColor(.green)
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Syncing with iCloud")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Your notes are automatically synced across all your Apple devices.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section("iCloud Sync") {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.icloud")
                                .foregroundColor(.orange)
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Not syncing with iCloud")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Your notes are only stored locally on this Mac.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button(action: moveToICloud) {
                            HStack {
                                if isMoving {
                                    ProgressView().scaleEffect(0.7)
                                    Text("Moving to iCloud Drive…")
                                } else {
                                    Image(systemName: "icloud.and.arrow.up")
                                    Text("Move Root to iCloud Drive")
                                }
                            }
                        }
                        .disabled(isMoving)

                        Text("This will create a **mdma** folder inside iCloud Drive, move all your notes there, and update the root folder setting.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            // MARK: Git
            Section("Git") {
                if git.isRepo {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(MarkdownParser.greenCol))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Git repository detected")
                                .font(.system(size: 13))
                            Text("Branch: \(git.currentBranch) · \(git.uncommittedCount) uncommitted")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Toggle("Auto-commit on save", isOn: $gitAutoCommit)
                    if gitAutoCommit {
                        Text("Each autosave will run git add + git commit for the current file.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                        Text("No git repository in the current root folder.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Text("To use git integration, initialise a repo in your notes folder: git init")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: isInICloud ? 920 : 1020)
        .onAppear { applyAppearance() }
    }

    private func applyAppearance() {
        switch appearanceMode {
        case "Dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        case "Light": NSApp.appearance = NSAppearance(named: .aqua)
        default:      NSApp.appearance = nil
        }
    }

    private func pick() {
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true
        p.canCreateDirectories = true; p.prompt = "Choose Root Folder"
        if p.runModal() == .OK, let url = p.url { fs.setRoot(url) }
    }

    private func moveToICloud() {
        guard let currentRoot = fs.rootURL else { return }

        // Find iCloud Drive Documents
        guard let iCloudDocs = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        )?.appendingPathComponent("Documents") else {
            // Fallback path
            let fallback = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs")
            moveRoot(from: currentRoot, to: fallback.appendingPathComponent("mdma"))
            return
        }

        moveRoot(from: currentRoot, to: iCloudDocs.appendingPathComponent("mdma"))
    }

    // MARK: - Theme helpers

    private func themeColors(for theme: Theme, dark: Bool) -> [Color] {
        dark
        ? [Color(theme.bgDark), Color(theme.sidebarDark), Color(theme.accent),
           Color(theme.contactCol), Color(theme.fileRefCol), Color(theme.linkColor)]
        : [Color(theme.bgLight), Color(theme.sidebarLight), Color(theme.accent),
           Color(theme.contactCol), Color(theme.fileRefCol), Color(theme.linkColor)]
    }

    private func moveRoot(from source: URL, to dest: URL) {
        isMoving  = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default

            // Create destination if needed
            if !fm.fileExists(atPath: dest.path) {
                try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            }

            // Move all contents of source into dest
            let contents = (try? fm.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )) ?? []

            var moveError: Error?
            for item in contents {
                let target = dest.appendingPathComponent(item.lastPathComponent)
                do {
                    if fm.fileExists(atPath: target.path) {
                        try fm.removeItem(at: target)
                    }
                    try fm.moveItem(at: item, to: target)
                } catch {
                    moveError = error
                }
            }

            DispatchQueue.main.async {
                isMoving = false
                if moveError == nil {
                    fs.setRoot(dest)
                }
            }
        }
    }
}

// MARK: - ThemeSwatchButton

private struct ThemeSwatchButton: View {
    let theme:      Theme
    let isSelected: Bool
    let action:     () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var dark: Bool { colorScheme == .dark }

    private var swatchColors: [Color] {
        dark
        ? [Color(theme.bgDark), Color(theme.sidebarDark),
           Color(theme.textDark), Color(theme.accent),
           Color(theme.contactCol), Color(theme.fileRefCol)]
        : [Color(theme.bgLight), Color(theme.sidebarLight),
           Color(theme.textLight), Color(theme.accent),
           Color(theme.contactCol), Color(theme.fileRefCol)]
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Mini palette preview
                HStack(spacing: 4) {
                    ForEach(swatchColors.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(swatchColors[i])
                            .frame(height: 18)
                    }
                }
                .padding(8)
                .background(
                    dark ? Color(theme.bgDark) : Color(theme.bgLight)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(theme.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 2)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
