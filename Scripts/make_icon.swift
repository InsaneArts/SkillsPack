// Draws the SkillsPack app icon: an open package on a deep graphite tile, one coloured light per agent.
// Usage: swift Scripts/make_icon.swift <out.png> [size]
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1024 : 1024
let s = CGFloat(size) / 1024

guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.scaleBy(x: s, y: s)
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
}
func polygon(_ points: [CGPoint]) -> CGPath {
    let p = CGMutablePath(); p.addLines(between: points); p.closeSubpath(); return p
}

// Body: the macOS icon grid leaves 100 pt of air around an 824 pt rounded square.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 824 * 0.2237
let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: CGColor(gray: 0, alpha: 0.42))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x16181F)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x101219), rgb(0x1E2232), rgb(0x2B3150)], [0, 0.6, 1]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
// Warm light from inside the box.
ctx.drawRadialGradient(gradient([rgb(0xF2A65A, 0.38), rgb(0xF2A65A, 0)], [0, 1]),
                       startCenter: CGPoint(x: 512, y: 600), startRadius: 0, endCenter: CGPoint(x: 512, y: 600), endRadius: 400, options: [])
ctx.restoreGState()

// The box, seen from slightly above: two side faces meeting at a front seam, an open top.
let cx: CGFloat = 512, w: CGFloat = 250, h: CGFloat = 270, d: CGFloat = 112
let seamBottom: CGFloat = 220, seamTop = seamBottom + h
let leftFace = polygon([CGPoint(x: cx - w, y: seamBottom + d), CGPoint(x: cx, y: seamBottom), CGPoint(x: cx, y: seamTop), CGPoint(x: cx - w, y: seamTop + d)])
let rightFace = polygon([CGPoint(x: cx, y: seamBottom), CGPoint(x: cx + w, y: seamBottom + d), CGPoint(x: cx + w, y: seamTop + d), CGPoint(x: cx, y: seamTop)])
let opening = polygon([CGPoint(x: cx, y: seamTop), CGPoint(x: cx + w, y: seamTop + d), CGPoint(x: cx, y: seamTop + 2 * d), CGPoint(x: cx - w, y: seamTop + d)])

// Inside of the box, dark, with the three agent lights rising out of it.
ctx.addPath(opening); ctx.setFillColor(rgb(0x0B0C10)); ctx.fillPath()
let lights: [(CGFloat, CGFloat, UInt32)] = [(-118, 70, 0xD9785A), (0, 120, 0x4079F5), (118, 70, 0x9461E0)]
for (dx, rise, color) in lights {
    let center = CGPoint(x: cx + dx, y: seamTop + d + rise)
    ctx.drawRadialGradient(gradient([rgb(color, 0.55), rgb(color, 0)], [0, 1]),
                           startCenter: center, startRadius: 0, endCenter: center, endRadius: 120, options: [])
    ctx.setFillColor(rgb(color)); ctx.fillEllipse(in: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
    ctx.setFillColor(rgb(0xFFFFFF, 0.35)); ctx.fillEllipse(in: CGRect(x: center.x - 26, y: center.y + 4, width: 36, height: 26))
}

// Cardboard faces, lit from the right.
ctx.saveGState(); ctx.addPath(leftFace); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xB9824F), rgb(0xD39A61)], [0, 1]), start: CGPoint(x: cx - w, y: seamBottom), end: CGPoint(x: cx, y: seamTop), options: [])
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(rightFace); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0xE2AE76), rgb(0xF0C08A)], [0, 1]), start: CGPoint(x: cx, y: seamBottom), end: CGPoint(x: cx + w, y: seamTop), options: [])
ctx.restoreGState()

// Open flaps folded back over the edges.
let flapLeft = polygon([CGPoint(x: cx - w, y: seamTop + d), CGPoint(x: cx, y: seamTop), CGPoint(x: cx - 40, y: seamTop - 70), CGPoint(x: cx - w - 70, y: seamTop + d - 40)])
let flapRight = polygon([CGPoint(x: cx, y: seamTop), CGPoint(x: cx + w, y: seamTop + d), CGPoint(x: cx + w + 70, y: seamTop + d - 40), CGPoint(x: cx + 40, y: seamTop - 70)])
ctx.addPath(flapLeft); ctx.setFillColor(rgb(0xA87245)); ctx.fillPath()
ctx.addPath(flapRight); ctx.setFillColor(rgb(0xC98F58)); ctx.fillPath()

// Edges.
ctx.setStrokeColor(rgb(0x3A2614, 0.55)); ctx.setLineWidth(5); ctx.setLineJoin(.round)
for path in [leftFace, rightFace, flapLeft, flapRight] { ctx.addPath(path); ctx.strokePath() }

guard let image = ctx.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(filePath: out))
