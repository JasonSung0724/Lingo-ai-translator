import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let inset: CGFloat = 90
let rect = NSRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
let radius: CGFloat = 200

ctx.saveGState()
let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
clip.addClip()
let grad = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.47, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.95, alpha: 1)
])!
grad.draw(in: rect, angle: -90)
ctx.restoreGState()

// Glyph "A文"
let text = "A文"
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 400, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: para
]
let astr = NSAttributedString(string: text, attributes: attrs)
let ts = astr.size()
astr.draw(in: NSRect(x: (size-ts.width)/2, y: (size-ts.height)/2, width: ts.width, height: ts.height))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: "/tmp/lingo_icon.png"))
print("wrote /tmp/lingo_icon.png")
