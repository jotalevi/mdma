import SwiftUI
import AppKit

// MARK: - Heading Entry

private struct HeadingEntry: Identifiable {
    let id   = UUID()
    let level: Int     // 1, 2, 3
    let text:  String
    let line:  Int     // 1-based line number
}

// MARK: - OutlinePanelView

struct OutlinePanelView: View {
    let content:  String
    let onSelect: (Int) -> Void   // passes 1-based line number

    @State private var hovered: UUID?

    private var headings: [HeadingEntry] {
        var result: [HeadingEntry] = []
        let lines = content.components(separatedBy: "\n")
        var inCode = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inCode.toggle(); continue }
            if inCode { continue }
            if trimmed.hasPrefix("#### ") { continue }   // skip H4+
            let level: Int
            let text:  String
            if      trimmed.hasPrefix("### ") { level = 3; text = String(trimmed.dropFirst(4)) }
            else if trimmed.hasPrefix("## ")  { level = 2; text = String(trimmed.dropFirst(3)) }
            else if trimmed.hasPrefix("# ")   { level = 1; text = String(trimmed.dropFirst(2)) }
            else { continue }
            result.append(HeadingEntry(level: level, text: text, line: i + 1))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Outline")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(MarkdownParser.mutedColor))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(MarkdownParser.sidebarColor))

            Divider().opacity(0.15)

            if headings.isEmpty {
                Spacer()
                Text("No headings")
                    .font(.system(size: 12))
                    .foregroundColor(Color(MarkdownParser.mutedColor).opacity(0.6))
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(headings) { entry in
                            HeadingRow(entry: entry, hovered: $hovered) {
                                onSelect(entry.line)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(Color(MarkdownParser.sidebarColor))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(MarkdownParser.mutedColor).opacity(0.15)),
            alignment: .leading
        )
    }
}

// MARK: - HeadingRow

private struct HeadingRow: View {
    let entry:    HeadingEntry
    @Binding var hovered: UUID?
    let action:   () -> Void

    private var isHovered: Bool { hovered == entry.id }

    private var indent: CGFloat {
        switch entry.level {
        case 1: return 14
        case 2: return 24
        default: return 34
        }
    }

    private var fontWeight: Font.Weight {
        entry.level == 1 ? .semibold : .regular
    }

    private var fontSize: CGFloat {
        switch entry.level {
        case 1: return 12.5
        case 2: return 12
        default: return 11.5
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Level indicator dot
                Circle()
                    .fill(Color(MarkdownParser.accent).opacity(entry.level == 1 ? 0.8 : 0.4))
                    .frame(width: entry.level == 1 ? 5 : 3.5,
                           height: entry.level == 1 ? 5 : 3.5)

                Text(entry.text)
                    .font(.system(size: fontSize, weight: fontWeight))
                    .foregroundColor(isHovered
                        ? Color(MarkdownParser.accent)
                        : Color(MarkdownParser.textColor).opacity(entry.level == 3 ? 0.7 : 1.0))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.leading, indent)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                isHovered
                    ? Color(MarkdownParser.accent).opacity(0.08)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovered = inside ? entry.id : nil
        }
    }
}
