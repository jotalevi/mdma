import SwiftUI

struct TinyScrollBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { setMini(v) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { setMini(v) }
    }
    private func setMini(_ v: NSView) {
        func walk(_ view: NSView) {
            if let scroller = view as? NSScroller { scroller.controlSize = .mini }
            view.subviews.forEach { walk($0) }
        }
        walk(v.window?.contentView ?? v)
    }
}
