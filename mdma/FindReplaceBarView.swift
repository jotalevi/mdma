import SwiftUI
import AppKit

// MARK: - FindMode

enum FindMode { case find, findReplace }

// MARK: - FindReplaceBarView

struct FindReplaceBarView: View {

    @Binding var isVisible: Bool
    @Binding var mode:      FindMode

    @State private var query:       String = ""
    @State private var replacement: String = ""
    @State private var matchCase:   Bool   = false
    @State private var matchCount:  Int    = 0
    @State private var matchIndex:  Int    = 0   // 1-based; 0 = none

    @FocusState private var findFocused:    Bool
    @FocusState private var replaceFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {

                // ── Find field ──────────────────────────────────────────
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(Color(MarkdownParser.muted))

                    TextField("Find", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(Color(MarkdownParser.text))
                        .focused($findFocused)
                        .onSubmit { findNext() }
                        .onChange(of: query) { _, _ in updateSearch() }

                    if !query.isEmpty {
                        if matchCount > 0 {
                            Text(matchIndex > 0 ? "\(matchIndex)/\(matchCount)" : "\(matchCount)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(MarkdownParser.muted))
                        } else {
                            Text("No matches")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.7))
                        }
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(MarkdownParser.muted))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(MarkdownParser.codeBg))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(findFocused
                                    ? Color(MarkdownParser.accent).opacity(0.5)
                                    : Color.clear, lineWidth: 1)
                        )
                )

                // ── Prev / Next ─────────────────────────────────────────
                HStack(spacing: 2) {
                    Button { findPrev() } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(BarIconButtonStyle())
                    .disabled(matchCount == 0)
                    .help("Previous match (⇧↵)")
                    .keyboardShortcut(.return, modifiers: .shift)

                    Button { findNext() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(BarIconButtonStyle())
                    .disabled(matchCount == 0)
                    .help("Next match (↵)")
                }

                // ── Match-case toggle ────────────────────────────────────
                Button {
                    matchCase.toggle()
                    updateSearch()
                } label: {
                    Image(systemName: "textformat")
                        .font(.system(size: 11))
                        .foregroundColor(matchCase
                            ? Color(MarkdownParser.accent)
                            : Color(MarkdownParser.muted))
                }
                .buttonStyle(BarIconButtonStyle(active: matchCase))
                .help("Match Case")

                if mode == .findReplace {
                    Divider().frame(height: 18).opacity(0.3)

                    // ── Replace field ────────────────────────────────────
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(Color(MarkdownParser.muted))

                        TextField("Replace", text: $replacement)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(Color(MarkdownParser.text))
                            .focused($replaceFocused)
                            .onSubmit { replaceOne() }

                        if !replacement.isEmpty {
                            Button { replacement = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(MarkdownParser.muted))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(MarkdownParser.codeBg))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(replaceFocused
                                        ? Color(MarkdownParser.accent).opacity(0.5)
                                        : Color.clear, lineWidth: 1)
                            )
                    )

                    Button("Replace") { replaceOne() }
                        .buttonStyle(BarTextButtonStyle())
                        .disabled(query.isEmpty || matchCount == 0)

                    Button("All") { replaceAll() }
                        .buttonStyle(BarTextButtonStyle())
                        .disabled(query.isEmpty || matchCount == 0)
                }

                Spacer()

                // ── Close ────────────────────────────────────────────────
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundColor(Color(MarkdownParser.muted))
                }
                .buttonStyle(BarIconButtonStyle())
                .help("Close (⎋)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(MarkdownParser.sidebarColor))

            Divider().opacity(0.12)
        }
        .onAppear {
            // Auto-focus find field when bar appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                findFocused = true
            }
            // Pre-fill with selected text if any
            if let tv = focusedTextView(), tv.selectedRange().length > 0 {
                let sel = (tv.string as NSString).substring(with: tv.selectedRange())
                query = sel
                updateSearch()
            }
        }
        .onDisappear {
            clearHighlights()
        }
        .onReceive(NotificationCenter.default.publisher(for: .findBarUpdateCount)) { note in
            if let count = note.userInfo?["count"] as? Int,
               let idx   = note.userInfo?["index"] as? Int {
                matchCount = count
                matchIndex = idx
            }
        }
        // ESC to close
        .background(
            Button("") { close() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        )
    }

    // MARK: - Actions

    private func updateSearch() {
        NotificationCenter.default.post(
            name: .findBarSearch,
            object: nil,
            userInfo: ["query": query, "matchCase": matchCase]
        )
    }

    private func findNext() {
        NotificationCenter.default.post(name: .findBarNext, object: nil)
    }

    private func findPrev() {
        NotificationCenter.default.post(name: .findBarPrev, object: nil)
    }

    private func replaceOne() {
        NotificationCenter.default.post(
            name: .findBarReplaceOne,
            object: nil,
            userInfo: ["replacement": replacement]
        )
    }

    private func replaceAll() {
        NotificationCenter.default.post(
            name: .findBarReplaceAll,
            object: nil,
            userInfo: ["replacement": replacement]
        )
    }

    private func clearHighlights() {
        NotificationCenter.default.post(name: .findBarClear, object: nil)
    }

    private func close() {
        clearHighlights()
        isVisible = false
    }

    private func focusedTextView() -> NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }
}

// MARK: - Button styles

private struct BarIconButtonStyle: ButtonStyle {
    var active: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(active
                ? Color(MarkdownParser.accent)
                : Color(MarkdownParser.muted))
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed
                        ? Color(MarkdownParser.muted).opacity(0.15)
                        : (active ? Color(MarkdownParser.accent).opacity(0.12) : Color.clear))
            )
            .contentShape(Rectangle())
    }
}

private struct BarTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundColor(Color(MarkdownParser.text))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(configuration.isPressed
                        ? Color(MarkdownParser.accent).opacity(0.2)
                        : Color(MarkdownParser.codeBg))
            )
    }
}

// MARK: - Notification names (find/replace)

extension Notification.Name {
    static let findBarSearch     = Notification.Name("mdma.findBarSearch")
    static let findBarNext       = Notification.Name("mdma.findBarNext")
    static let findBarPrev       = Notification.Name("mdma.findBarPrev")
    static let findBarReplaceOne = Notification.Name("mdma.findBarReplaceOne")
    static let findBarReplaceAll = Notification.Name("mdma.findBarReplaceAll")
    static let findBarClear      = Notification.Name("mdma.findBarClear")
    static let findBarUpdateCount = Notification.Name("mdma.findBarUpdateCount")
    static let findBarShow       = Notification.Name("mdma.findBarShow")
}
