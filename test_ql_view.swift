import AppKit
import QuickLookUI

let ql = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), style: .normal)!
print(ql.subviews)
