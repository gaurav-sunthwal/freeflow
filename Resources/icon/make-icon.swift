// Renders the FreeFlow app icon. Usage: swift make-icon.swift <out.png> <size>
import AppKit

let args = CommandLine.arguments
let out = args[1], size = CGFloat(Double(args[2]) ?? 1024)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let s = size / 1024
// Draw in a 1024pt, y-down design space.
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: s, y: -s)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)!
}
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
/// Fills `path` with a linear gradient running from `a` to `b`.
func fill(_ path: CGPath, _ g: CGGradient, _ a: CGPoint, _ b: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// macOS icon grid: 824pt squircle centred in 1024 canvas.
let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow + violet outer glow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: CGColor(gray: 0, alpha: 0.4))
ctx.addPath(squircle); ctx.setFillColor(rgb(0x0a0918)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 22 * s, color: rgb(0x6a4cff, 0.35))
ctx.addPath(squircle); ctx.setFillColor(rgb(0x0a0918)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
// Near-black body with a soft indigo glow rising from the top and behind the mark.
fill(squircle, gradient([rgb(0x0d0b22), rgb(0x050409)], [0, 1]), p(512, 100), p(512, 924))
let glow = gradient([rgb(0x5b3dff, 0.22), rgb(0x5b3dff, 0)], [0, 1])
ctx.drawRadialGradient(glow, startCenter: p(512, 60), startRadius: 0, endCenter: p(512, 60), endRadius: 520, options: [])
ctx.drawRadialGradient(glow, startCenter: p(540, 520), startRadius: 0, endCenter: p(540, 520), endRadius: 380, options: [])

// The "F": two flowing ribbons sharing a tail at bottom-left, with a dark fold between them.
let topRibbon = CGMutablePath()
topRibbon.move(to: p(236, 812))
topRibbon.addCurve(to: p(390, 352), control1: p(262, 640), control2: p(292, 432))
topRibbon.addCurve(to: p(640, 282), control1: p(460, 296), control2: p(550, 286))
topRibbon.addCurve(to: p(812, 228), control1: p(724, 278), control2: p(780, 262))
topRibbon.addCurve(to: p(700, 432), control1: p(800, 320), control2: p(768, 400))
topRibbon.addCurve(to: p(452, 470), control1: p(620, 466), control2: p(520, 448))
topRibbon.addCurve(to: p(236, 812), control1: p(350, 510), control2: p(290, 640))
topRibbon.closeSubpath()

let fold = CGMutablePath()
fold.move(to: p(236, 812))
fold.addCurve(to: p(452, 452), control1: p(286, 630), control2: p(340, 494))
fold.addCurve(to: p(730, 420), control1: p(540, 424), control2: p(650, 450))
fold.addCurve(to: p(560, 548), control1: p(700, 500), control2: p(640, 540))
fold.addCurve(to: p(236, 812), control1: p(420, 570), control2: p(300, 640))
fold.closeSubpath()

let midRibbon = CGMutablePath()
midRibbon.move(to: p(236, 812))
midRibbon.addCurve(to: p(400, 572), control1: p(270, 700), control2: p(320, 610))
midRibbon.addCurve(to: p(640, 516), control1: p(470, 540), control2: p(560, 540))
midRibbon.addCurve(to: p(780, 446), control1: p(700, 500), control2: p(745, 480))
midRibbon.addCurve(to: p(640, 618), control1: p(762, 540), control2: p(716, 598))
midRibbon.addCurve(to: p(400, 660), control1: p(560, 640), control2: p(470, 636))
midRibbon.addCurve(to: p(236, 812), control1: p(320, 690), control2: p(270, 750))
midRibbon.closeSubpath()

ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 30 * s, color: rgb(0x2a12a8, 0.6))
fill(fold, gradient([rgb(0x1a0f7a), rgb(0x3b25e0), rgb(0x2a18b0)], [0, 0.6, 1]), p(260, 760), p(720, 430))
fill(midRibbon, gradient([rgb(0x7a4dff), rgb(0x7f8cff), rgb(0x7cc8ff)], [0, 0.5, 1]), p(250, 800), p(760, 470))
fill(topRibbon, gradient([rgb(0xa98cff), rgb(0xf6f3ff), rgb(0xe6dcff), rgb(0xa874ff)], [0, 0.32, 0.55, 1]),
     p(240, 800), p(810, 240))
// Specular sheen along the top edge of the upper ribbon.
fill(topRibbon, gradient([CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)], [0, 1]), p(500, 280), p(520, 420))

// Thin violet rim around the squircle.
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addPath(squircle); ctx.setLineWidth(7); ctx.setStrokeColor(rgb(0x6b4dff, 0.7)); ctx.strokePath()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
