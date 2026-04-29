import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text:         String
    @Binding var selectedText: String
    
    // MARK: - Make
    
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.backgroundColor = MarkdownParser.bg
        scroll.drawsBackground = true
        scroll.verticalScroller?.controlSize = .mini
        scroll.horizontalScroller?.controlSize = .mini
        
        let size = scroll.contentSize
        let tc = NSTextContainer(containerSize: NSSize(width: size.width, height: .greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        let lm = NSLayoutManager(); lm.addTextContainer(tc)
        let ts = NSTextStorage(); ts.addLayoutManager(lm)
        
        let tv = MarkdownTextView(frame: NSRect(origin: .zero, size: size), textContainer: tc)
        tv.minSize = NSSize(width: 0, height: size.height)
        tv.maxSize = NSSize(width: Swift.Double.greatestFiniteMagnitude, height: Swift.Double.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.delegate = context.coordinator
        
        tv.onTextChange = { newText in
            DispatchQueue.main.async {
                context.coordinator.lastLoadedText = newText
                context.coordinator.onTextChange?(newText)
            }
        }

        tv.onSelectionChange = { sel in
            DispatchQueue.main.async {
                context.coordinator.onSelectionChange?(sel)
            }
        }
        
        scroll.documentView = tv
        tv.load(text)
        
        DispatchQueue.main.async {
            scroll.verticalScroller?.controlSize = .mini
        }
        
        return scroll
    }
    
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // Always keep coordinator callbacks fresh so they capture current bindings
        context.coordinator.onTextChange = { newText in
            self.text = newText
        }
        context.coordinator.onSelectionChange = { sel in
            self.selectedText = sel
        }
        
        guard let tv = scroll.documentView as? MarkdownTextView else { return }
        // Only reload when switching files — compare against last loaded text identity
        if context.coordinator.lastLoadedText != text {
            context.coordinator.lastLoadedText = text
            tv.load(text)
        }
    }
    // MARK: - Coordinator
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChange:     ((String) -> Void)?
        var onSelectionChange: ((String) -> Void)?
        var lastLoadedText: String = ""

        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? MarkdownTextView)?.cursorMoved()
        }
    }
}

