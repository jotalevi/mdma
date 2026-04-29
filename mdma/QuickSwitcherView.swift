import SwiftUI
import AppKit

// MARK: - QuickSwitcherView

struct QuickSwitcherView: View {
    @Binding var isShowing: Bool
    let onSelect: (URL) -> Void

    @ObservedObject private var fs = FileSystemManager.shared

    @State private var query:       String = ""
    @State private var selectedIdx: Int    = 0
    @FocusState private var focused: Bool

    // All .md files in the workspace, flat
    private var allFiles: [URL] {
        flatFiles(fs.tree)
    }

    private func flatFiles(_ items: [FileItem]) -> [URL] {
        items.flatMap { $0.isDirectory ? flatFiles($0.children ?? []) : [$0.url] }
    }

    // Fuzzy-filtered results
    private var results: [URL] {
        guard !query.isEmpty else { return Array(allFiles.prefix(20)) }
        let q = query.lowercased()
        return allFiles
            .compactMap { url -> (URL, Int)? in
                let name = url.deletingPathExtension().lastPathComponent.lowercased()
                if let score = fuzzyScore(name, query: q) {
                    return (url, score)
                }
                return nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
            .prefix(20)
            .map { $0 }
    }

    // Simple fuzzy scorer: consecutive bonus + match length penalty
    private func fuzzyScore(_ str: String, query: String) -> Int? {
        var si = str.startIndex
        var qi = query.startIndex
        var score = 0
        var consecutive = 0
        while si < str.endIndex && qi < query.endIndex {
            if str[si] == query[qi] {
                consecutive += 1
                score += consecutive * 2
                qi = query.index(after: qi)
            } else {
                consecutive = 0
            }
            si = str.index(after: si)
        }
        return qi == query.endIndex ? score : nil
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop — click to dismiss
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(MarkdownParser.mutedColor))
                        .font(.system(size: 14))

                    TextField("Open file…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundColor(Color(MarkdownParser.textColor))
                        .focused($focused)
                        .onSubmit { confirmSelection() }

                    if !query.isEmpty {
                        Button {
                            query = ""
                            selectedIdx = 0
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color(MarkdownParser.mutedColor))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().opacity(0.15)

                // Results list
                if results.isEmpty {
                    Text("No files found")
                        .font(.system(size: 13))
                        .foregroundColor(Color(MarkdownParser.mutedColor))
                        .padding(.vertical, 24)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(results.enumerated()), id: \.offset) { idx, url in
                                    SwitcherRow(
                                        url: url,
                                        isSelected: idx == selectedIdx,
                                        query: query
                                    ) {
                                        select(url)
                                    }
                                    .id(idx)
                                }
                            }
                        }
                        .frame(maxHeight: 340)
                        .onChange(of: selectedIdx) { _, newIdx in
                            withAnimation { proxy.scrollTo(newIdx, anchor: .center) }
                        }
                    }
                }
            }
            .background(Color(MarkdownParser.sidebarColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 28, x: 0, y: 8)
            .frame(width: 480)
            .onAppear {
                focused = true
                selectedIdx = 0
            }
            .onKeyPress(.upArrow)   { moveSelection(-1); return .handled }
            .onKeyPress(.downArrow) { moveSelection( 1); return .handled }
            .onKeyPress(.escape)    { dismiss(); return .handled }
            .onChange(of: query) { selectedIdx = 0 }
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selectedIdx = (selectedIdx + delta + count) % count
    }

    private func confirmSelection() {
        guard selectedIdx < results.count else { return }
        select(results[selectedIdx])
    }

    private func select(_ url: URL) {
        dismiss()
        onSelect(url)
    }

    private func dismiss() {
        query = ""
        isShowing = false
    }
}

// MARK: - SwitcherRow

private struct SwitcherRow: View {
    let url:        URL
    let isSelected: Bool
    let query:      String
    let action:     () -> Void

    @State private var hovered = false

    private var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }

    private var folderName: String {
        url.deletingLastPathComponent().lastPathComponent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(Color(MarkdownParser.accent).opacity(0.8))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(highlightedName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    if !folderName.isEmpty {
                        Text(folderName)
                            .font(.system(size: 11))
                            .foregroundColor(Color(MarkdownParser.mutedColor))
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                (isSelected || hovered)
                    ? Color(MarkdownParser.accent).opacity(0.12)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    // Highlight matched characters in the file name
    private var highlightedName: AttributedString {
        var attributed = AttributedString(displayName)
        guard !query.isEmpty else { return attributed }
        let lower = displayName.lowercased()
        var qi = query.startIndex
        for ci in lower.indices {
            guard qi < query.endIndex else { break }
            if lower[ci] == query[qi] {
                let offset = lower.distance(from: lower.startIndex, to: ci)
                let start  = attributed.index(attributed.startIndex, offsetByCharacters: offset)
                let end    = attributed.index(start, offsetByCharacters: 1)
                attributed[start..<end].foregroundColor = MarkdownParser.accent
                attributed[start..<end].font = .system(size: 13).bold()
                qi = query.index(after: qi)
            }
        }
        return attributed
    }
}
