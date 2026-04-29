import SwiftUI
import Contacts
import UniformTypeIdentifiers

struct SnippetText: View {
    let text: String
    let query: String

    var body: some View {
        let ns    = text as NSString
        let range = ns.range(of: query, options: .caseInsensitive)
        if range.location == NSNotFound {
            return AnyView(
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(Color(MarkdownParser.muted))
                    .lineLimit(1)
            )
        }
        let before = ns.substring(to: range.location)
        let match  = ns.substring(with: range)
        let after  = ns.substring(from: range.location + range.length)
        return AnyView(
            Text("\(before)\(Text(match).foregroundColor(Color(MarkdownParser.accent)).bold())\(after)")
                .font(.system(size: 11))
                .foregroundColor(Color(MarkdownParser.muted))
                .lineLimit(1)
        )
    }
}



struct SidebarView: View {
    @EnvironmentObject var fs:           FileSystemManager
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject    private var git = GitManager.shared
    @Binding var detail:  Detail
    @Binding var search:  String
    var content:      String = ""
    var selectedText: String = ""
    @AppStorage("showFileExtensions")  private var showFileExtensions  = true
    @AppStorage("showWordCount")       private var showWordCount        = true
    @AppStorage("gitAutoCommit")       private var gitAutoCommit        = false

    // Keyboard nav
    @State private var focusedURL: URL?
    @State private var expandedFolders: Set<URL> = []
    @FocusState private var focused: Bool
    @FocusState private var searchFocused: Bool

    // Inline editing
    @State private var editingURL: URL?
    @State private var editingText: String = ""
    @State private var editingOriginal: String = ""
    @State private var isNewItem: Bool = false
    @State private var newIsFolder: Bool = false
    @State private var newParent: URL?

    // Clipboard (for file cut/copy/paste)
    @State private var clipboardURL: URL?
    @State private var clipIsCut: Bool = false

    // Delete confirmation
    @State private var confirmDeleteURL: URL?

    // Organization
    @State private var showArchive:   Bool = false
    @State private var showTemplates: Bool = false
    @State private var templatePickerNote: URL? = nil  // note near which to create from template

    // Flattened visible list for arrow key navigation
    var visibleNav: [(url: URL, isFolder: Bool)] {
        guard let root = fs.rootURL else { return [] }
        var result = [(url: root, isFolder: true)]
        if expandedFolders.contains(root) {
            result += flatNav(fs.tree)
        }
        return result
    }

    func flatNav(_ items: [FileItem]) -> [(url: URL, isFolder: Bool)] {
        items.flatMap { item -> [(url: URL, isFolder: Bool)] in
            let entry = (url: item.url, isFolder: item.isDirectory)
            if item.isDirectory && expandedFolders.contains(item.url) {
                return [entry] + flatNav(item.children ?? [])
            }
            return [entry]
        }
    }

    var searchHits: [SearchHit]? {
        guard !search.isEmpty else { return nil }
        return fs.search(search)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider().opacity(0.12)
            ScrollViewReader { proxy in
                ScrollView {
                        if let hits = searchHits {
                            sectionLabel("\(hits.count) result\(hits.count == 1 ? "" : "s")")
                            ForEach(hits) { hit in
                                searchHitRow(hit)
                            }
                        } else {
                            pinnedSection
                            if let root = fs.rootURL {
                                rootRow(root: root)
                                if expandedFolders.contains(root) {
                                    if isNewItem && newParent == root {
                                        inlineEditorRow(depth: 1)
                                    }
                                    treeRows(fs.tree, depth: 1)
                                }
                            }
                            archiveSection
                            //backlinksSection
                            tagsSection
                            referencesSection
                        }
                }
                .background(TinyScrollBar())
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(phases: .down) { press in
                    handleKey(press, proxy: proxy)
                }
                .onAppear {
                    if let root = fs.rootURL {
                        expandedFolders.insert(root)
                        focusedURL = root
                    }
                    focused = true
                }
                .onChange(of: fs.rootURL) {
                    if let root = fs.rootURL { expandedFolders.insert(root); focusedURL = root }
                }
            }

            if showWordCount, case .note = detail, !content.isEmpty {
                wordCountBar
            }
        }
        .background(Color(MarkdownParser.sidebar))
        .onReceive(NotificationCenter.default.publisher(for: .focusSidebar)) { _ in
            focused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                searchFocused = true
            }
        }
        .confirmationDialog(
            "Move \"\(confirmDeleteURL?.lastPathComponent ?? "")\" to Trash?",
            isPresented: Binding(get: { confirmDeleteURL != nil }, set: { if !$0 { confirmDeleteURL = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let url = confirmDeleteURL {
                    NotificationCenter.default.post(name: .closeTabForURL, object: url)
                    fs.delete(url)
                    focusedURL = fs.rootURL
                }
                confirmDeleteURL = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteURL = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Key Handler

    func handleKey(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        // While inline editor is active, only handle Escape at this level
        if editingURL != nil || isNewItem {
            if press.key == .escape { cancelEdit(); return .handled }
            return .ignored
        }

        let nav = visibleNav
        let idx = focusedURL.flatMap { u in nav.firstIndex(where: { $0.url == u }) } ?? -1

        switch press.key {

        case .upArrow:
            if idx > 0 {
                focusedURL = nav[idx - 1].url
                proxy.scrollTo(focusedURL, anchor: .center)
            }
            return .handled

        case .downArrow:
            if idx < nav.count - 1 {
                focusedURL = nav[idx + 1].url
                proxy.scrollTo(focusedURL, anchor: .center)
            }
            return .handled

        case .leftArrow:
            guard let f = focusedURL else { return .ignored }
            if nav.first(where: { $0.url == f })?.isFolder == true && expandedFolders.contains(f) {
                expandedFolders.remove(f)
            } else {
                let parent = f.deletingLastPathComponent()
                if nav.contains(where: { $0.url == parent }) {
                    focusedURL = parent
                    proxy.scrollTo(parent, anchor: .center)
                }
            }
            return .handled

        case .rightArrow:
            guard let f = focusedURL else { return .ignored }
            let isFolder = nav.first(where: { $0.url == f })?.isFolder ?? false
            if isFolder {
                if !expandedFolders.contains(f) {
                    expandedFolders.insert(f)
                } else if idx + 1 < nav.count {
                    focusedURL = nav[idx + 1].url
                    proxy.scrollTo(focusedURL, anchor: .center)
                }
            } else {
                detail = .note(f)
            }
            return .handled

        case .return:
            guard let f = focusedURL else { return .ignored }
            let isFolder = nav.first(where: { $0.url == f })?.isFolder ?? false
            if isFolder {
                if expandedFolders.contains(f) { expandedFolders.remove(f) }
                else { expandedFolders.insert(f) }
            } else {
                detail = .note(f)
            }
            return .handled

        case .space:
            guard let f = focusedURL else { return .ignored }
            let isFolder = nav.first(where: { $0.url == f })?.isFolder ?? false
            if isFolder {
                if expandedFolders.contains(f) { expandedFolders.remove(f) }
                else { expandedFolders.insert(f) }
            } else {
                detail = .note(f)
            }
            return .handled

        case .delete:
            if press.modifiers.contains(.command), let f = focusedURL {
                confirmDeleteURL = f
                return .handled
            }
            return .ignored

        default:
            guard press.modifiers.contains(.command) else { return .ignored }
            switch press.characters.lowercased() {
            case "r":
                if let f = focusedURL {
                    let nav = visibleNav
                    let isFolder = nav.first(where: { $0.url == f })?.isFolder ?? false
                    let name = isFolder ? f.lastPathComponent : f.deletingPathExtension().lastPathComponent
                    editingURL      = f
                    editingOriginal = name
                    editingText     = name
                    isNewItem       = false
                    newParent       = nil
                }
                return .handled
            case "c":
                if let f = focusedURL { clipboardURL = f; clipIsCut = false }
                return .handled
            case "x":
                if let f = focusedURL { clipboardURL = f; clipIsCut = true }
                return .handled
            case "v":
                pasteFile()
                return .handled
            case "n":
                if press.modifiers.contains(.shift) {
                    startNew(isFolder: true, near: focusedURL)
                } else {
                    startNew(isFolder: false, near: focusedURL)
                }
                return .handled
            default:
                return .ignored
            }
        }
    }

    // MARK: - Root Row

    @ViewBuilder
    func rootRow(root: URL) -> some View {
        let isFocused = focusedURL == root
        let expanded  = expandedFolders.contains(root)
        HStack(spacing: 7) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color(MarkdownParser.muted))
                .frame(width: 10)
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(MarkdownParser.accent).opacity(0.9))
            Text("mdma")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(MarkdownParser.text))
            Spacer()
        }
        .padding(.leading, 12).padding(.trailing, 12).padding(.vertical, 7)
        .background(isFocused ? (focused ? Color(MarkdownParser.accent).opacity(0.12) : Color.gray.opacity(0.1)) : .clear)
        .contentShape(Rectangle())
        .id(root)
        .onTapGesture {
            focused = true
            focusedURL = root
            if expanded { expandedFolders.remove(root) } else { expandedFolders.insert(root) }
        }
        .contextMenu {
            Button("New Note")   { startNew(isFolder: false, near: root) }
            Button("New Folder") { startNew(isFolder: true,  near: root) }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { drop(into: root, providers: $0) }
    }

    // MARK: - Recursive Tree

    func treeRows(_ items: [FileItem], depth: Int) -> AnyView {
        AnyView(
            ForEach(items) { item in
                treeItem(item, depth: depth)
            }
        )
    }

    func treeItem(_ item: FileItem, depth: Int) -> AnyView {
        if item.isDirectory {
            return AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    folderRow(item, depth: depth)
                    if expandedFolders.contains(item.url) {
                        if isNewItem && newParent == item.url {
                            inlineEditorRow(depth: depth + 1)
                        }
                        ForEach(item.children ?? []) { child in
                            treeItem(child, depth: depth + 1)
                        }
                    }
                }
            )
        } else if editingURL == item.url {
            return AnyView(inlineEditorRow(depth: depth, isRename: true, item: item))
        } else {
            return AnyView(fileRow(item, depth: depth))
        }
    }

    @ViewBuilder
    func folderRow(_ item: FileItem, depth: Int) -> some View {
        let isFocused = focusedURL == item.url
        let expanded  = expandedFolders.contains(item.url)

        if editingURL == item.url {
            inlineEditorRow(depth: depth, isRename: true, item: item)
        } else {
            HStack(spacing: 7) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(MarkdownParser.muted))
                    .frame(width: 10)
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundColor(Color(MarkdownParser.accent).opacity(0.7))
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(MarkdownParser.muted))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 16 + 4)
            .padding(.trailing, 12).padding(.vertical, 7)
            .background(isFocused ? (focused ? Color(MarkdownParser.accent).opacity(0.12) : Color.gray.opacity(0.1)) : .clear)
            .contentShape(Rectangle())
            .id(item.url)
            .onTapGesture {
                focused = true
                focusedURL = item.url
                if expanded { expandedFolders.remove(item.url) }
                else { expandedFolders.insert(item.url) }
            }
            .onDrag { dragProvider(for: item.url) }
            .onDrop(of: [.fileURL], isTargeted: nil) { drop(into: item.url, providers: $0) }
            .contextMenu {
                Button("New Note Here")   { startNew(isFolder: false, near: item.url, forceFolder: item.url) }
                Button("New Subfolder")   { startNew(isFolder: true,  near: item.url, forceFolder: item.url) }
                Divider()
                Button("Rename") { beginRename(item) }
                Divider()
                Button("Delete", role: .destructive) { confirmDeleteURL = item.url }
            }
        }
    }

    @ViewBuilder
    func fileRow(_ item: FileItem, depth: Int) -> some View {
        let selected  = detail == .note(item.url)
        let isFocused = focusedURL == item.url
        HStack(spacing: 0) {
            Rectangle()
                .fill(selected ? (focused ? Color(MarkdownParser.accent) : Color.gray.opacity(0.35)) : .clear)
                .frame(width: 2)
            HStack(spacing: 6) {
                Text(item.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(selected ? Color(MarkdownParser.heading) : Color(MarkdownParser.text))
                    .lineLimit(1)
                if fs.isPinned(item.url) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(MarkdownParser.accent).opacity(0.65))
                        .rotationEffect(.degrees(45))
                }
                Spacer()
                // Git status dot
                if git.isRepo, let root = fs.rootURL {
                    let rel = item.url.path.replacingOccurrences(of: root.path + "/", with: "")
                    if let status = git.statuses[rel] {
                        Circle()
                            .fill(gitDotColor(status))
                            .frame(width: 6, height: 6)
                            .help(gitDotLabel(status))
                    }
                }
            }
            .padding(.leading, CGFloat(depth) * 16 + 8)
            .padding(.trailing, 12).padding(.vertical, 7)
        }
        .background(
            isFocused
                ? (focused
                    ? Color(MarkdownParser.accent).opacity(selected ? 0.18 : 0.12)
                    : Color.gray.opacity(0.1))
                : (selected
                    ? (focused ? Color(MarkdownParser.accent).opacity(0.1) : Color.gray.opacity(0.07))
                    : .clear)
        )
        .contentShape(Rectangle())
        .id(item.url)
        .onTapGesture {
            focused = true
            focusedURL = item.url
            detail = .note(item.url)
        }
        .onDrag { dragProvider(for: item.url) }
        .contextMenu {
            Button("Rename") { beginRename(item) }
            Divider()
            if fs.isPinned(item.url) {
                Button("Unpin") { fs.unpin(item.url) }
            } else {
                Button("Pin to Top") { fs.pin(item.url) }
            }
            Button("Archive") { fs.archive(item.url) }
            if !fs.templateItems.isEmpty || true {
                Button("Save as Template…") {
                    if let content = fs.rawContent(item.url) {
                        fs.saveAsTemplate(name: item.displayName, content: content)
                    }
                }
            }
            Divider()
            Button("Copy")  { clipboardURL = item.url; clipIsCut = false }
            Button("Cut")   { clipboardURL = item.url; clipIsCut = true  }
            Divider()
            Button("Delete", role: .destructive) { confirmDeleteURL = item.url }
        }
    }

    // MARK: - Inline Editor

    @ViewBuilder
    func inlineEditorRow(depth: Int, isRename: Bool = false, item: FileItem? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isRename
                ? (item?.isDirectory == true ? "folder" : "doc.text")
                : (newIsFolder ? "folder" : "doc.text"))
                .font(.system(size: 12))
                .foregroundColor(Color(MarkdownParser.accent))
            FocusedTextField(text: $editingText,
                             onSubmit: { isRename ? commitRename() : commitNew() },
                             onEscape: { cancelEdit() })
                .font(.system(size: 13))
        }
        .padding(.leading, CGFloat(depth) * 16 + 10)
        .padding(.trailing, 12).padding(.vertical, 6)
        .background(Color(MarkdownParser.accent).opacity(0.1))
    }

    // MARK: - Tags

    @ViewBuilder
    var tagsSection: some View {
        if !fs.allTags.isEmpty {
            Divider().opacity(0.08).padding(.top, 4)
            sectionLabel("TAGS")
            ForEach(fs.allTags, id: \.self) { tag in
                Button { detail = .tag(tag) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.system(size: 11))
                            .foregroundColor(Color(MarkdownParser.accent))
                        Text("\(tag)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Color(MarkdownParser.accent))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Text("\(fs.files(withTag: tag).count)")
                            .font(.system(size: 10))
                            .foregroundColor(Color(MarkdownParser.muted))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Backlinks Section
    @ViewBuilder
    var backlinksSection: some View {
        if case .note(let url) = detail {
            let links = fs.backlinkIndex[url] ?? []
            if !links.isEmpty {
                Divider().opacity(0.08)
                sectionLabel("LINKED BY")
                ForEach(links, id: \.self) { src in
                    Button {
                        // Use the same notification-based path as Quick Switcher / Graph view
                        // so the tab bar, editor, and content state all update together.
                        NotificationCenter.default.post(name: .openFile, object: src)
                    } label: {
                        HStack(spacing: 8) {
                            Text(src.deletingPathExtension().lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .foregroundColor(Color(MarkdownParser.muted))
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 4)
                        .background(Color(MarkdownParser.accent).opacity(0.0))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Git helpers
    private func gitDotColor(_ status: GitFileStatus) -> Color {
        switch status {
        case .modified: return Color.orange
        case .untracked, .staged: return Color(MarkdownParser.greenCol)
        case .deleted:  return Color.red
        case .renamed:  return Color.blue
        }
    }

    private func gitDotLabel(_ status: GitFileStatus) -> String {
        switch status {
        case .modified:  return "Modified"
        case .untracked: return "Untracked"
        case .staged:    return "Staged"
        case .deleted:   return "Deleted"
        case .renamed:   return "Renamed"
        }
    }

    @ViewBuilder
    func searchHitRow(_ hit: SearchHit) -> some View {
        let isActive = detail == .note(hit.url)
        Button {
            detail = .note(hit.url)
            // Open file then jump to line
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(
                    name: .scrollToLine,
                    object: nil,
                    userInfo: ["line": hit.line, "matchRange": hit.matchRange]
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(hit.url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(MarkdownParser.heading))
                    Spacer()
                    Text("L\(hit.line)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(MarkdownParser.muted))
                }
                SnippetText(text: hit.lineText, query: search)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(isActive ? Color(MarkdownParser.accent).opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
        Divider().opacity(0.06).padding(.leading, 14)
    }
    
        @ViewBuilder
        var referencesSection: some View {
            let contacts = fs.references.filter { if case .contact = $0.kind { return true }; return false }
            let fileRefs = fs.references.filter { if case .fileRef = $0.kind { return true }; return false }
            let links    = fs.references.filter { if case .link    = $0.kind { return true }; return false }

            if !fs.references.isEmpty {
                //Divider().opacity(0.08).padding(.top, 4)
                //sectionLabel("REFERENCES")

                if !contacts.isEmpty {
                    sectionLabel("CONTACTS")
                    ForEach(contacts) { ref in
                        if case .contact(let name) = ref.kind {
                            Button {
                                if !ContactsManager.shared.authorized {
                                       ContactsManager.shared.requestAccess()
                                   } else if let contact = ContactsManager.shared.find(name) {
                                       let url = URL(string: "addressbook://\(contact.identifier)")!
                                       NSWorkspace.shared.open(url)
                                   } else {
                                       NSWorkspace.shared.open(URL(string: "addressbook://")!)
                                   }                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.circle")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(MarkdownParser.contactCol))
                                    Text("\(name)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(Color(MarkdownParser.contactCol))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    Text(ref.sourceNote.deletingPathExtension().lastPathComponent)
                                        .font(.system(size: 9))
                                        .foregroundColor(Color(MarkdownParser.muted))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 4)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                if !fileRefs.isEmpty {
                    sectionLabel("FILES")
                    ForEach(fileRefs) { ref in
                        if case .fileRef(let name,  _) = ref.kind {
                            Button {
                                if let refFolder = FileSystemManager.shared.refsFolder {
                                    let fileURL = refFolder.appendingPathComponent(name)
                                    if FileManager.default.fileExists(atPath: fileURL.path) {
                                        NSWorkspace.shared.open(fileURL)
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(MarkdownParser.fileRefCol))
                                    Text(showFileExtensions ? name : (URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent))
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(MarkdownParser.fileRefCol))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    Text(ref.sourceNote.deletingPathExtension().lastPathComponent)
                                        .font(.system(size: 9))
                                        .foregroundColor(Color(MarkdownParser.muted))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 4)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                if !links.isEmpty {
                    sectionLabel("LINKS")
                    ForEach(links) { ref in
                        if case .link(let url) = ref.kind {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "link")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(MarkdownParser.linkColor))
                                    Text(ref.display)
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(MarkdownParser.linkColor))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer()
                                    Text(ref.sourceNote.deletingPathExtension().lastPathComponent)
                                        .font(.system(size: 9))
                                        .foregroundColor(Color(MarkdownParser.muted))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 4)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                Spacer().frame(height: 12)
            }
        }

        @ViewBuilder func refSubLabel(_ s: String) -> some View {
            Text(s.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(1)
                .foregroundColor(Color(MarkdownParser.muted).opacity(0.6))
                .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 2)
        }

    // MARK: - Actions

    func startNew(isFolder: Bool, near url: URL?, forceFolder: URL? = nil) {
        let folder: URL
        if let forced = forceFolder {
            folder = forced
        } else if let u = url {
            let nav = visibleNav
            folder = nav.first(where: { $0.url == u })?.isFolder == true
                ? u : u.deletingLastPathComponent()
        } else {
            folder = fs.rootURL ?? URL(fileURLWithPath: NSHomeDirectory())
        }
        expandedFolders.insert(folder)
        isNewItem   = true
        newIsFolder = isFolder
        newParent   = folder
        editingURL  = nil
        editingText = ""
    }

    func beginRename(_ item: FileItem) {
        editingURL      = item.url
        editingOriginal = item.displayName
        editingText     = item.displayName
        isNewItem       = false
        newParent       = nil
    }

    func commitNew() {
        guard let parent = newParent else { cancelEdit(); return }
        let raw = editingText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { cancelEdit(); return }

        // Support "path/to/file" syntax
        let parts = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var current = parent
        for (i, part) in parts.enumerated() {
            let isLast = i == parts.count - 1
            if isLast && !newIsFolder {
                if let url = fs.createFile(in: current, name: part) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        detail = .note(url)
                        focusedURL = url
                    }
                }
            } else {
                let next = current.appendingPathComponent(part)
                if !FileManager.default.fileExists(atPath: next.path) {
                    _ = fs.createFolder(in: current, name: part)
                }
                expandedFolders.insert(next)
                current = next
            }
        }
        cancelEdit()
    }

    func commitRename() {
        guard let url = editingURL else { cancelEdit(); return }
        let name = editingText.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty && name != editingOriginal {
            if let newURL = fs.rename(url, to: name) {
                if case .note(let open) = detail, open == url { detail = .note(newURL) }
                focusedURL = newURL
                NotificationCenter.default.post(name: .fileURLDidChange, object: nil,
                                                userInfo: ["old": url, "new": newURL])
            }
        }
        cancelEdit()
    }

    func cancelEdit() {
        editingURL  = nil
        editingText = ""
        isNewItem   = false
        newParent   = nil
        focused     = true
    }

    func pasteFile() {
        guard let src = clipboardURL else { return }
        let nav = visibleNav
        let dest: URL
        if let f = focusedURL, nav.first(where: { $0.url == f })?.isFolder == true { dest = f }
        else if let f = focusedURL { dest = f.deletingLastPathComponent() }
        else if let root = fs.rootURL { dest = root }
        else { return }

        if clipIsCut {
            if let dst = fs.move(src, to: dest) {
                NotificationCenter.default.post(name: .fileURLDidChange, object: nil,
                                                userInfo: ["old": src, "new": dst])
            }
            clipboardURL = nil
        } else { fs.copyFile(src, to: dest) }
    }

    // MARK: - Drag & Drop

    func dragProvider(for url: URL) -> NSItemProvider {
        NSItemProvider(object: url as NSURL)
    }

    func drop(into folder: URL, providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var srcURL: URL?
                if let data = item as? Data { srcURL = URL(dataRepresentation: data, relativeTo: nil) }
                else if let url = item as? URL { srcURL = url }
                if let src = srcURL {
                    DispatchQueue.main.async {
                        if let dst = self.fs.move(src, to: folder) {
                            NotificationCenter.default.post(name: .fileURLDidChange, object: nil,
                                                            userInfo: ["old": src, "new": dst])
                        }
                    }
                }
            }
            handled = true
        }
        return handled
    }

    // MARK: - Header & Search

    // MARK: - Pinned Section

    @ViewBuilder
    var pinnedSection: some View {
        let pinned = fs.pinnedURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !pinned.isEmpty {
            sectionLabel("PINNED")
            ForEach(pinned, id: \.self) { url in
                let item = FileItem(url: url)
                let selected = detail == .note(url)
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(selected ? Color(MarkdownParser.accent) : .clear)
                        .frame(width: 2)
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color(MarkdownParser.accent).opacity(0.7))
                        Text(item.displayName)
                            .font(.system(size: 13))
                            .foregroundColor(selected ? Color(MarkdownParser.heading) : Color(MarkdownParser.text))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 7)
                }
                .background(selected ? Color(MarkdownParser.accent).opacity(0.1) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { detail = .note(url) }
                .contextMenu {
                    Button("Unpin") { fs.unpin(url) }
                    Divider()
                    Button("Archive") { fs.archive(url) }
                    Divider()
                    Button("Delete", role: .destructive) { confirmDeleteURL = url }
                }
            }
            Divider().opacity(0.08).padding(.vertical, 2)
        }
    }

    // MARK: - Archive Section
    @ViewBuilder
    var archiveSection: some View {
        if !fs.archiveItems.isEmpty {
            Divider().opacity(0.08).padding(.top, 4)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showArchive.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showArchive ? "archivebox.fill" : "archivebox")
                        .font(.system(size: 10))
                    Text("ARCHIVE")
                        .font(.system(size: 10, weight: .semibold)).tracking(1)
                    Spacer()
                    Text("\(fs.archiveItems.count)")
                        .font(.system(size: 10))
                    Image(systemName: showArchive ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                }
                .foregroundColor(Color(MarkdownParser.muted))
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            }
            .buttonStyle(.plain)

            if showArchive {
                ForEach(fs.archiveItems) { item in
                    let selected = detail == .note(item.url)
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(selected ? Color(MarkdownParser.muted) : .clear)
                            .frame(width: 2)
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 11))
                                .foregroundColor(Color(MarkdownParser.muted).opacity(0.6))
                            Text(item.displayName)
                                .font(.system(size: 12))
                                .foregroundColor(Color(MarkdownParser.muted))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 6)
                    }
                    .background(selected ? Color(MarkdownParser.muted).opacity(0.08) : .clear)
                    .contentShape(Rectangle())
                    .onTapGesture { detail = .note(item.url) }
                    .contextMenu {
                        Button("Unarchive") { fs.unarchive(item.url) }
                        Divider()
                        Button("Delete", role: .destructive) { confirmDeleteURL = item.url }
                    }
                }
            }
        }
    }

    // MARK: - Word Count Bar (sidebar bottom)
    private var wordCountBar: some View {
        let source   = selectedText.isEmpty ? content : selectedText
        let hasSelection = !selectedText.isEmpty
        let words = source.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
        let chars = source.unicodeScalars.count
        let lines = source.components(separatedBy: "\n").count
        return HStack(spacing: 8) {
            Spacer()
            if hasSelection {
                Text("sel:")
                    .foregroundColor(Color(MarkdownParser.accent).opacity(0.7))
            }
            Text("\(words)w")
            Text("·").opacity(0.3)
            Text("\(chars)c")
            Text("·").opacity(0.3)
            Text("\(lines)l")
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundColor(Color(MarkdownParser.mutedColor).opacity(0.7))
        .frame(height: 22)
        .padding(.trailing, 10)
        .background(Color(MarkdownParser.sidebar))
        .overlay(Divider().opacity(0.1), alignment: .top)
        .animation(.easeInOut(duration: 0.1), value: hasSelection)
    }

    var header: some View {
        HStack {
            Spacer()
            // Template picker
            if !fs.templateItems.isEmpty {
                Menu {
                    ForEach(fs.templateItems) { tpl in
                        Button(tpl.displayName) {
                            if let url = fs.createFromTemplate(tpl.url, near: focusedURL) {
                                detail = .note(url)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "doc.badge.plus").font(.system(size: 13))
                        .foregroundColor(Color(MarkdownParser.accent))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("New from Template")
            }

            Button { startNew(isFolder: false, near: focusedURL) } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 13))
                    .foregroundColor(Color(MarkdownParser.accent))
            }.buttonStyle(.plain).help("New Note (⌘N)")
            Button { startNew(isFolder: true, near: focusedURL) } label: {
                Image(systemName: "folder.badge.plus").font(.system(size: 13))
                    .foregroundColor(Color(MarkdownParser.accent))
            }.buttonStyle(.plain).help("New Folder (⌘⇧N)")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundColor(Color(MarkdownParser.muted))
            TextField("Search…", text: $search)
                .textFieldStyle(.plain).font(.system(size: 12))
                .foregroundColor(Color(MarkdownParser.text))
                .focused($searchFocused)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                        .foregroundColor(Color(MarkdownParser.muted))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(MarkdownParser.codeBg))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(searchFocused
                            ? Color(MarkdownParser.accent).opacity(0.45)
                            : Color.clear, lineWidth: 1)
                )
        )
        .padding(.horizontal, 10).padding(.bottom, 8)
    }

    @ViewBuilder func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .semibold)).tracking(1)
            .foregroundColor(Color(MarkdownParser.muted))
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
    }

    @ViewBuilder func searchRow(_ item: FileItem) -> some View {
        Button { detail = .note(item.url) } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text").font(.system(size: 12))
                    .foregroundColor(Color(MarkdownParser.muted))
                Text(item.displayName).font(.system(size: 13))
                    .foregroundColor(Color(MarkdownParser.text)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }.buttonStyle(.plain)
    }

    func flatSearch(_ items: [FileItem], query: String) -> [FileItem] {
        items.flatMap { item -> [FileItem] in
            if item.isDirectory { return flatSearch(item.children ?? [], query: query) }
            let nameMatch    = item.displayName.localizedCaseInsensitiveContains(query)
            let contentMatch = (fs.rawContent(item.url) ?? "").localizedCaseInsensitiveContains(query)
            return (nameMatch || contentMatch) ? [item] : []
        }
    }
}

struct FocusedTextField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.font = .systemFont(ofSize: 13)
        tf.textColor = MarkdownParser.text
        tf.focusRingType = .none
        tf.delegate = context.coordinator
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        if tf.stringValue != text { tf.stringValue = text }
        // Focus + select all on first appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard tf.window?.firstResponder !== tf.currentEditor() else { return }
            tf.window?.makeFirstResponder(tf)
            tf.currentEditor()?.selectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusedTextField
        init(_ p: FocusedTextField) { parent = p }

        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField { parent.text = tf.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.onSubmit(); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.onEscape(); return true }
            return false
        }
    }
}
