import SwiftUI

struct GitCommitSheet: View {
    @Binding var message:     String
    @Binding var isPresented: Bool
    var onCommit: (String) -> Void

    @ObservedObject private var git = GitManager.shared
    @FocusState private var focused: Bool

    private var placeholder: String {
        let date = DateFormatter.localizedString(from: Date(),
                                                 dateStyle: .medium, timeStyle: .short)
        return "Update notes – \(date)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(Color(MarkdownParser.accent))
                Text("Commit Changes")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(MarkdownParser.heading))
                Spacer()
                Text(git.currentBranch)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(MarkdownParser.muted))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(MarkdownParser.codeBg))
                    .cornerRadius(4)
            }

            // Changed files summary
            if git.uncommittedCount > 0 {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(git.uncommittedCount) file(s) changed")
                        .font(.system(size: 11))
                        .foregroundColor(Color(MarkdownParser.muted))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(git.statuses.keys.prefix(8)), id: \.self) { path in
                                HStack(spacing: 6) {
                                    statusBadge(git.statuses[path]!)
                                    Text(path)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(Color(MarkdownParser.text))
                                        .lineLimit(1)
                                }
                            }
                            if git.uncommittedCount > 8 {
                                Text("… and \(git.uncommittedCount - 8) more")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(MarkdownParser.muted))
                            }
                        }
                    }
                    .frame(maxHeight: 72)
                }
                .padding(8)
                .background(Color(MarkdownParser.codeBg))
                .cornerRadius(6)
            }

            // Message field
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13))
                        .foregroundColor(Color(MarkdownParser.muted))
                        .padding(.top, 4).padding(.leading, 2)
                }
                TextEditor(text: $message)
                    .font(.system(size: 13))
                    .frame(height: 52)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .padding(6)
            .background(Color(MarkdownParser.codeBg))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(focused ? Color(MarkdownParser.accent).opacity(0.4) : Color.clear,
                            lineWidth: 1)
            )

            // Actions
            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.plain)
                    .foregroundColor(Color(MarkdownParser.muted))
                Spacer()
                Button("Commit All") {
                    let msg = message.isEmpty ? placeholder : message
                    onCommit(msg)
                    message = ""
                    isPresented = false
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(Color(MarkdownParser.accent))
                .disabled(git.uncommittedCount == 0)
            }
        }
        .padding(20)
        .background(Color(MarkdownParser.bg))
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func statusBadge(_ status: GitFileStatus) -> some View {
        let (letter, color): (String, Color) = {
            switch status {
            case .modified:  return ("M", .orange)
            case .untracked: return ("U", Color(MarkdownParser.greenCol))
            case .staged:    return ("A", .blue)
            case .deleted:   return ("D", .red)
            case .renamed:   return ("R", .purple)
            }
        }()
        Text(letter)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 14, height: 14)
            .background(color)
            .cornerRadius(3)
    }
}
