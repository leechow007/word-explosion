#!/usr/bin/env swift
// 词爆 WordPop 应用图标生成（1024px 主图，之后由 build_app.sh 缩放并生成 .icns）
import AppKit
import Foundation

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in

    // ---- 背景：靛蓝 → 紫 → 粉 的柔和对角渐变，带内阴影质感
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)
    let bgColors = [
        NSColor(calibratedRed: 0.36, green: 0.34, blue: 0.98, alpha: 1),   // #5C57FA
        NSColor(calibratedRed: 0.60, green: 0.38, blue: 0.95, alpha: 1),   // #9961F2
        NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.71, alpha: 1)    // #FF8CB5
    ]
    NSGradient(colors: bgColors)?.draw(in: bgPath, angle: 135)

    // 顶部高光，模拟玻璃
    let gloss = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 223, yRadius: 223)
    NSColor.white.withAlphaComponent(0.10).setFill()
    gloss.fill()

    // ---- 装饰：漂浮的小玻璃泡泡
    func glassCircle(x: CGFloat, y: CGFloat, r: CGFloat, alpha: CGFloat) {
        let p = NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        NSColor.white.withAlphaComponent(alpha).setFill()
        p.fill()
        let rim = NSBezierPath(ovalIn: NSRect(x: x - r + 1, y: y - r + 1, width: r * 2 - 2, height: r * 2 - 2))
        NSColor.white.withAlphaComponent(alpha * 0.5).setStroke()
        rim.lineWidth = 2
        rim.stroke()
    }
    glassCircle(x: 170, y: 850, r: 46, alpha: 0.16)
    glassCircle(x: 880, y: 860, r: 34, alpha: 0.13)
    glassCircle(x: 150, y: 160, r: 30, alpha: 0.12)
    glassCircle(x: 890, y: 180, r: 58, alpha: 0.10)

    // 小星星
    func spark(x: CGFloat, y: CGFloat, r: CGFloat) {
        let p = NSBezierPath()
        let points: [(CGFloat, CGFloat)] = [(0, 1), (0.24, 0.24), (1, 0), (0.24, -0.24), (0, -1),
                                            (-0.24, -0.24), (-1, 0), (-0.24, 0.24)]
        for (i, pt) in points.enumerated() {
            let px = x + pt.0 * r, py = y + pt.1 * r
            if i == 0 { p.move(to: NSPoint(x: px, y: py)) } else { p.line(to: NSPoint(x: px, y: py)) }
        }
        p.close()
        NSColor.white.withAlphaComponent(0.85).setFill()
        p.fill()
    }
    spark(x: 300, y: 720, r: 20)
    spark(x: 750, y: 240, r: 26)

    // ---- 主胶囊：白色毛玻璃词条 "Pop"
    let capsuleW: CGFloat = 560
    let capsuleH: CGFloat = 250
    let cx = (rect.width - capsuleW) / 2
    let cy: CGFloat = 330
    let main = NSBezierPath(roundedRect: NSRect(x: cx, y: cy, width: capsuleW, height: capsuleH),
                            xRadius: capsuleH / 2, yRadius: capsuleH / 2)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.2, alpha: 0.28)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.white.withAlphaComponent(0.94).setFill()
    main.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    let wordStyle = NSMutableParagraphStyle()
    wordStyle.alignment = .center
    let popFont = NSFont.systemFont(ofSize: 148, weight: .heavy)
    let attr: [NSAttributedString.Key: Any] = [
        .font: popFont,
        .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.25, alpha: 1),
        .paragraphStyle: wordStyle
    ]
    let str = NSAttributedString(string: "Pop", attributes: attr)
    let strSize = str.size()
    str.draw(in: NSRect(x: cx + (capsuleW - strSize.width) / 2,
                        y: cy + (capsuleH - strSize.height) / 2,
                        width: strSize.width, height: strSize.height))

    // ---- 顶部小胶囊 "Word"
    let topW: CGFloat = 330
    let topH: CGFloat = 124
    let topX = cx - 40
    let topY = cy + capsuleH + 18
    let top = NSBezierPath(roundedRect: NSRect(x: topX, y: topY, width: topW, height: topH),
                           xRadius: topH / 2, yRadius: topH / 2)
    NSColor.white.withAlphaComponent(0.90).setFill()
    top.fill()

    let wordFont = NSFont.systemFont(ofSize: 72, weight: .bold)
    let attr2: [NSAttributedString.Key: Any] = [
        .font: wordFont,
        .foregroundColor: NSColor(calibratedRed: 0.42, green: 0.36, blue: 0.94, alpha: 1),
        .paragraphStyle: wordStyle
    ]
    let str2 = NSAttributedString(string: "Word", attributes: attr2)
    let str2Size = str2.size()
    str2.draw(in: NSRect(x: topX + (topW - str2Size.width) / 2,
                         y: topY + (topH - str2Size.height) / 2,
                         width: str2Size.width, height: str2Size.height))

    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("icon render failed")
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "build")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let out = outDir.appendingPathComponent("icon-1024.png")
try png.write(to: out)
print("icon written: \(out.path)")
