import SwiftUI
import UniformTypeIdentifiers

// MARK: - Detail

enum Detail: Equatable {
    case note(URL), tag(String), none
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var fs:           FileSystemManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.openWindow) private var openWindow

    @AppStorage("autosave")    private var autosave    = true
    @AppStorage("showOutline") private var showOutline = false

    @State private var detail:        Detail  = .none
    @State private var content:       String  = ""
    @State private var selectedText:  String  = ""
    @State private var search:       String  = ""
    @State private var openTabs:     [URL]   = []
    @State private var activeTab:    URL?    = nil
    @State private var showSidebar:  Bool    = true
    @State private var sidebarWidth: CGFloat = 230
    @State private var unsavedTabs:  Set<URL> = []

    @State private var tabScrollPositions:  [URL: CGFloat] = [:]
    @State private var tabCursorPositions:  [URL: NSRange]  = [:]
    @State private var showQuickSwitcher:   Bool = false
    @State private var showFindBar:         Bool = false
    @State private var findBarMode:         FindMode = .find
    @State private var showGraph:           Bool = false
    @State private var showCommitSheet:     Bool = false
    @State private var commitMessage:       String = ""
    @ObservedObject private var git = GitManager.shared
    @AppStorage("gitAutoCommit") private var gitAutoCommit = false

    var body: some View {
        Group {
            if fs.rootURL == nil {
                RootSetupView(detail: $detail)
            } else {
                mainLayout
            }
        }
        .background(TrafficLightHider())
        .onReceive(NotificationCenter.default.publisher(for: .newNote))   { _ in createNote() }
        .onReceive(NotificationCenter.default.publisher(for: .newFolder)) { _ in createFolder() }
        .onReceive(NotificationCenter.default.publisher(for: .closeTab))  { _ in
            if let url = activeTab { closeTab(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .insertFileRef)) { note in
            if let filename = note.object as? String {
                NotificationCenter.default.post(name: .insertText, object: "|\(filename)|")
                return
            }
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let src = panel.url else { return }
            if let name = FileSystemManager.shared.addFileReference(src) {
                NotificationCenter.default.post(name: .insertText, object: "|\(name)|")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { note in
            guard let url = note.object as? URL else { return }
            detail = .note(url)
            if let line = note.userInfo?["line"] as? Int, line > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: .scrollToLine, object: nil,
                                                    userInfo: ["line": line])
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tearOffTab)) { note in
            guard let url = note.object as? URL else { return }
            openNewWindow(for: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFocus)) { _ in
            toggleFocus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTabForURL)) { note in
            if let url = note.object as? URL { closeTab(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fileURLDidChange)) { note in
            guard let old = note.userInfo?["old"] as? URL,
                  let new = note.userInfo?["new"] as? URL else { return }
            remapTabURL(from: old, to: new)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            // Always save on app blur regardless of autosave setting (safe fallback)
            if let url = activeTab { fs.save(content, to: url) }
        }
        .onChange(of: detail) { handleDetailChange() }
    }

    // MARK: - Main Layout

    var mainLayout: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(detail: $detail, search: $search, content: content, selectedText: selectedText)
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)

                Color(MarkdownParser.sidebarColor)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .opacity(0.3)
                    .gesture(DragGesture().onChanged { v in
                        sidebarWidth = max(160, min(400, sidebarWidth + v.translation.width))
                    })
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
            }

            VStack(spacing: 0) {
                topBar
                Divider().opacity(0.12)
                // Find / Replace bar (slides in below top bar)
                if showFindBar, case .note = detail {
                    FindReplaceBarView(isVisible: $showFindBar, mode: $findBarMode)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
                ZStack(alignment: .topTrailing) {
                    editorArea
                    if showOutline, case .note = detail {
                        OutlinePanelView(content: content) { line in
                            NotificationCenter.default.post(name: .scrollToLine, object: nil,
                                                            userInfo: ["line": line])
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: showOutline)
            }
            .animation(.easeInOut(duration: 0.15), value: showFindBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .overlay(alignment: .center) {
            if showQuickSwitcher {
                QuickSwitcherView(isShowing: $showQuickSwitcher) { url in
                    detail = .note(url)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if showGraph {
                GraphView(isShowing: $showGraph) { url in
                    detail = .note(url)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.12), value: showQuickSwitcher)
        .animation(.easeInOut(duration: 0.14), value: showGraph)
    }

    // MARK: - Top Bar

    var topBar: some View {
        HStack(spacing: 0) {
            // Sidebar toggle
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13))
                    .foregroundColor(Color(MarkdownParser.mutedColor))
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, !showSidebar ? 72 : 0)

            Divider().frame(height: 20).opacity(0.2)

            
            // Native tab bar
            TabBarNSView(
                tabs:        $openTabs,
                activeTab:   $activeTab,
                unsavedTabs: $unsavedTabs,
                onSelect:    { switchTab(to: $0) },
                onClose:     { closeTab($0) },
                onReorder:   { openTabs = $0 },
                onTearOff:   { openNewWindow(for: $0) }
            )
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
            Spacer(minLength: 0)
            
            // Outline toggle (only when a note is open)
            if case .note = detail {
                Divider().frame(height: 20).opacity(0.2)
                Button {
                    withAnimation { showOutline.toggle() }
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 13))
                        .foregroundColor(showOutline
                            ? Color(MarkdownParser.accent)
                            : Color(MarkdownParser.mutedColor))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Outline (⌘L)")
                .background(
                    Button("") { withAnimation { showOutline.toggle() } }
                        .keyboardShortcut("l", modifiers: .command)
                        .hidden()
                )
            }

            // Quick switcher button
            Divider().frame(height: 20).opacity(0.2)
            Button {
                withAnimation { showQuickSwitcher = true }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(Color(MarkdownParser.mutedColor))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Quick Switcher (⌘P)")
            .background(
                Group {
                    // ⌘P — primary shortcut
                    Button("") { withAnimation { showQuickSwitcher = true } }
                        .keyboardShortcut("p", modifiers: .command)
                        .hidden()
                    // ⌘K — kept for muscle memory
                    Button("") { withAnimation { showQuickSwitcher = true } }
                        .keyboardShortcut("k", modifiers: .command)
                        .hidden()
                    // ⌘⇧F — focus sidebar search (show sidebar first if hidden)
                    Button("") {
                        if !showSidebar { withAnimation(.easeInOut(duration: 0.18)) { showSidebar = true } }
                        NotificationCenter.default.post(name: .focusSearch, object: nil)
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .hidden()
                }
            )

            // Graph button
            Divider().frame(height: 20).opacity(0.2)
            Button {
                withAnimation { showGraph = true }
            } label: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13))
                    .foregroundColor(showGraph ? Color(MarkdownParser.accent) : Color(MarkdownParser.mutedColor))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Note Graph")

            // Git status button (only when in a git repo)
            if git.isRepo {
                Divider().frame(height: 20).opacity(0.2)
                Button { showCommitSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                        if !git.currentBranch.isEmpty {
                            Text(git.currentBranch)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        if git.uncommittedCount > 0 {
                            Text("\(git.uncommittedCount)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(MarkdownParser.bg))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    .foregroundColor(git.uncommittedCount > 0
                        ? Color.orange
                        : Color(MarkdownParser.mutedColor))
                    .frame(height: 36)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Git: \(git.uncommittedCount) uncommitted change(s)")
                .sheet(isPresented: $showCommitSheet) {
                    GitCommitSheet(message: $commitMessage, isPresented: $showCommitSheet) { msg in
                        git.commitAll(message: msg)
                    }
                    .frame(width: 380, height: 200)
                }
            }

            // Share button
            if let url = activeTab {
                Divider().frame(height: 20).opacity(0.2)
                ShareButton(url: url, content: content)
                    .frame(width: 40, height: 36)
            }
        }
        .frame(height: 36)
        .background(Color(MarkdownParser.sidebarColor))
    }

    // MARK: - Editor Area

    @ViewBuilder
    var editorArea: some View {
        switch detail {
        case .note:
            MarkdownEditorView(
                text: Binding(
                    get: { content },
                    set: { v in
                        content = v
                        if autosave {
                            if let url = activeTab {
                                fs.save(v, to: url)
                                if gitAutoCommit {
                                    let name = url.deletingPathExtension().lastPathComponent
                                    git.commitFile(url, message: "auto: \(name)")
                                }
                            }
                        } else {
                            if let url = activeTab { unsavedTabs.insert(url) }
                        }
                    }
                ),
                selectedText: $selectedText
            )
            .background(
                Group {
                    Button("") { manualSave() }
                        .keyboardShortcut("s", modifiers: .command)
                        .hidden()
                    // ⌘F — Find
                    Button("") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            findBarMode = .find
                            showFindBar = true
                        }
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .hidden()
                    // ⌘H — Find & Replace
                    Button("") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            findBarMode = .findReplace
                            showFindBar = true
                        }
                    }
                    .keyboardShortcut("h", modifiers: .command)
                    .hidden()
                }
            )
        case .tag(let tag):
            TagResultsView(tag: tag, detail: $detail)
        case .none:
            EmptyStateView { createNote() }
        }
    }


    // MARK: - Tab Logic

    private func handleDetailChange() {
        if case .note(let url) = detail {
            if !openTabs.contains(url) { openTabs.append(url) }
            if activeTab != url {
                saveCurrentFile()
                saveScrollPosition(for: activeTab)
                activeTab    = url
                content      = fs.rawContent(url) ?? ""
                selectedText = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    restoreScrollPosition(for: url)
                }
            }
        }
    }

    private func switchTab(to url: URL) {
        saveCurrentFile()
        saveScrollPosition(for: activeTab)
        activeTab    = url
        detail       = .note(url)
        content      = fs.rawContent(url) ?? ""
        selectedText = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            restoreScrollPosition(for: url)
        }
    }

    private func closeTab(_ url: URL) {
        saveScrollPosition(for: url)
        if activeTab == url {
            // Always save on close regardless of autosave setting (prevent data loss)
            fs.save(content, to: url)
        }
        unsavedTabs.remove(url)
        tabScrollPositions.removeValue(forKey: url)
        tabCursorPositions.removeValue(forKey: url)
        openTabs.removeAll { $0 == url }
        if activeTab == url {
            activeTab = openTabs.last
            if let next = activeTab {
                detail  = .note(next)
                content = fs.rawContent(next) ?? ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    restoreScrollPosition(for: next)
                }
            } else {
                detail  = .none
                content = ""
            }
        }
    }

    private func saveCurrentFile() {
        // Respects the autosave setting; called on tab switch, app blur, etc.
        guard autosave else { return }
        if let url = activeTab { fs.save(content, to: url) }
    }

    private func manualSave() {
        guard let url = activeTab else { return }
        fs.save(content, to: url)
        unsavedTabs.remove(url)
    }

    // MARK: - Scroll position save/restore

    private func saveScrollPosition(for url: URL?) {
        guard let url, let tv = activeMarkdownTextView() else { return }
        tabScrollPositions[url] = tv.enclosingScrollView?.contentView.bounds.origin.y ?? 0
        tabCursorPositions[url] = tv.selectedRange()
    }

    private func restoreScrollPosition(for url: URL) {
        guard let tv = activeMarkdownTextView() else { return }
        if let y = tabScrollPositions[url] {
            tv.enclosingScrollView?.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
        }
        if let cursor = tabCursorPositions[url] {
            let safe = NSRange(location: min(cursor.location, tv.string.utf16.count), length: 0)
            tv.setSelectedRange(safe)
        }
    }

    private func remapTabURL(from old: URL, to new: URL) {
        if let i = openTabs.firstIndex(of: old) { openTabs[i] = new }
        if activeTab == old {
            activeTab = new
            detail    = .note(new)
        }
        if let scroll = tabScrollPositions.removeValue(forKey: old) { tabScrollPositions[new] = scroll }
        if let cursor = tabCursorPositions.removeValue(forKey: old)  { tabCursorPositions[new]  = cursor }
    }

    private func toggleFocus() {
        guard let window = NSApp.keyWindow else { return }
        if window.firstResponder is MarkdownTextView {
            // Editor is focused → move focus to sidebar
            NotificationCenter.default.post(name: .focusSidebar, object: nil)
        } else {
            // Sidebar (or elsewhere) is focused → move focus to editor
            if let tv = activeMarkdownTextView() {
                window.makeFirstResponder(tv)
            }
        }
    }

    private func activeMarkdownTextView() -> MarkdownTextView? {
        func find(in view: NSView) -> MarkdownTextView? {
            if let tv = view as? MarkdownTextView { return tv }
            for sub in view.subviews { if let f = find(in: sub) { return f } }
            return nil
        }
        return NSApp.keyWindow?.contentView.flatMap { find(in: $0) }
    }

    // MARK: - Create

    private func targetFolder() -> URL {
        if case .note(let url) = detail { return url.deletingLastPathComponent() }
        return fs.rootURL ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    private func createNote() {
        guard let url = fs.createFile(in: targetFolder()) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { detail = .note(url) }
    }

    private func createFolder() {
        fs.createFolder(in: targetFolder())
    }

    // MARK: - Tear-off new window

    private func openNewWindow(for url: URL) {
        let scroll = tabScrollPositions[url] ?? 0
        let payload = DetachedTabPayload(
            urlString:    url.absoluteString,
            scrollOffset: Double(scroll)
        )
        openWindow(id: "detached", value: payload)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            closeTab(url)
        }
    }
}

// MARK: - DetachedTabPayload

struct DetachedTabPayload: Codable, Hashable {
    let urlString:    String
    let scrollOffset: Double
    var url: URL? { URL(string: urlString) }
}

// MARK: - Detached Window View

struct DetachedWindowView: View {
    @EnvironmentObject var fs: FileSystemManager
    let payload: DetachedTabPayload

    @State private var content: String = ""
    @State private var didRestoreScroll: Bool = false
    @State private var selectedText: String = ""

    var url: URL? { payload.url }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let url {
                MarkdownEditorView(
                    text: Binding(
                        get: { content },
                        set: { v in
                            content = v
                            fs.save(v, to: url)
                        }
                    ),
                    selectedText: $selectedText
                )
                .onAppear {
                    content = fs.rawContent(url) ?? ""

                    DispatchQueue.main.async {
                        if let window = NSApp.keyWindow {
                            window.setFrameOrigin(NSPoint(
                                x: NSEvent.mouseLocation.x - window.frame.width  / 2,
                                y: NSEvent.mouseLocation.y - window.frame.height
                            ))
                        }
                    }

                    // Restore scroll position
                    if !didRestoreScroll {
                        didRestoreScroll = true
                        let y = CGFloat(payload.scrollOffset)
                        guard y > 0 else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            func find(in view: NSView) -> MarkdownTextView? {
                                if let tv = view as? MarkdownTextView { return tv }
                                for sub in view.subviews { if let f = find(in: sub) { return f } }
                                return nil
                            }
                            if let window = NSApp.windows.first(where: { $0.isKeyWindow }),
                               let tv = find(in: window.contentView ?? NSView()) {
                                tv.enclosingScrollView?.contentView
                                    .setBoundsOrigin(NSPoint(x: 0, y: y))
                            }
                        }
                    }
                }

                ShareButton(url: url, content: content)
                    .padding(.top, 10)
                    .padding(.trailing, 4)
            }
        }
        .background(Color(MarkdownParser.backgroundColor))
        .background(TrafficLightHider())
        .frame(minWidth: 500, minHeight: 400)
        .ignoresSafeArea()
    }
}

// MARK: - Share Button

struct ShareButton: View {
    let url: URL
    let content: String
    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 13))
                .foregroundColor(Color(MarkdownParser.mutedColor))
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Share")
        .background(SharingServicePicker(isPresented: $showPicker, url: url))
    }
}

struct SharingServicePicker: NSViewRepresentable {
    @Binding var isPresented: Bool
    let url: URL
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented else { return }
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: [self.url])
            picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
            self.isPresented = false
        }
    }
}

// MARK: - Traffic Light Hider

struct TrafficLightHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { apply(to: v.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: v.window) }
    }
    private func apply(to window: NSWindow?) {
        guard let w = window else { return }
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.styleMask.insert(.fullSizeContentView)
        w.standardWindowButton(.closeButton)?.isHidden      = false
        w.standardWindowButton(.miniaturizeButton)?.isHidden = false
        w.standardWindowButton(.zoomButton)?.isHidden        = false
    }
}

// MARK: - Root Setup

struct RootSetupView: View {
    @EnvironmentObject var fs: FileSystemManager
    @Binding var detail: Detail

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 50, weight: .ultraLight))
                .foregroundColor(Color(MarkdownParser.accentColor))
            Text("Welcome to mdma")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Color(MarkdownParser.headingColor))
            Text("Choose a folder on your Mac to store your notes.\nPoint it at iCloud Drive to sync across devices.")
                .font(.system(size: 13))
                .foregroundColor(Color(MarkdownParser.mutedColor))
                .multilineTextAlignment(.center)
            Button("Choose Folder…") { pick() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(Color(MarkdownParser.accentColor))
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(MarkdownParser.backgroundColor))
    }

    private func pick() {
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true
        p.canCreateDirectories = true; p.prompt = "Choose Root Folder"
        guard p.runModal() == .OK, let url = p.url else { return }
        fs.setRoot(url)
        fs.createWelcomeFileIfNeeded()
        let welcome = url.appendingPathComponent("welcome.md")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            detail = .note(welcome)
        }
    }
}

// MARK: - Tag Results

struct TagResultsView: View {
    @EnvironmentObject var fs: FileSystemManager
    let tag: String
    @Binding var detail: Detail
    var files: [URL] { fs.files(withTag: tag) }

    var body: some View {
        let hits: [(url: URL, line: Int, snippet: String)] = files.flatMap { url -> [(URL, Int, String)] in
            guard let content = fs.rawContent(url) else { return [] }
            return content.components(separatedBy: "\n").enumerated().compactMap { i, line in
                let hit = line.localizedCaseInsensitiveContains("$\(tag)$") ||
                          line.localizedCaseInsensitiveContains("$\(tag) ")
                return hit ? (url, i + 1, line.trimmingCharacters(in: .whitespaces)) : nil
            }
        }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                TagChip(tag: tag)
                Text("\(files.count) note\(files.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(Color(MarkdownParser.mutedColor))
            }
            .padding(.horizontal, 24).padding(.vertical, 16)

            Divider().opacity(0.12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(hits, id: \.1) { url, line, snippet in
                        Button {
                            detail = .note(url)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                NotificationCenter.default.post(
                                    name: .scrollToLine, object: nil,
                                    userInfo: ["line": line])
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text").font(.system(size: 10))
                                        .foregroundColor(Color(MarkdownParser.accent))
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color(MarkdownParser.headingColor))
                                    Spacer()
                                    Text("L\(line)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(Color(MarkdownParser.mutedColor))
                                }
                                Text(snippet)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(MarkdownParser.mutedColor))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 24).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.08).padding(.leading, 24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(MarkdownParser.backgroundColor))
    }
}

// MARK: - Shared UI

struct TagChip: View {
    let tag: String
    var body: some View {
        Text("$\(tag)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(Color(MarkdownParser.backgroundColor))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(MarkdownParser.accentColor))
            .cornerRadius(4)
    }
}

struct EmptyStateView: View {
    let onNew: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundColor(Color(MarkdownParser.mutedColor).opacity(0.4))

            Text("No note selected")
                .font(.system(size: 13))
                .foregroundColor(Color(MarkdownParser.mutedColor).opacity(0.6))

            Button("New Note") { onNew() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color(MarkdownParser.accentColor).opacity(0.15))
                .foregroundColor(Color(MarkdownParser.accentColor))
                .cornerRadius(7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

