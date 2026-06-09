import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])!
}

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawText(_ s: String, fontName: String, size: CGFloat, color: CGColor, cx: CGFloat, cy: CGFloat) {
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        .init(kCTFontAttributeName as String): font,
        .init(kCTForegroundColorAttributeName as String): color
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    let w = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
    ctx.textPosition = CGPoint(x: cx - w/2, y: cy - (ascent - descent)/2)
    CTLineDraw(line, ctx)
}

// 1) 背景渐变 squircle
ctx.saveGState()
ctx.addPath(roundedPath(CGRect(x: 0, y: 0, width: S, height: S), 228))
ctx.clip()
let grad = CGGradient(colorsSpace: cs,
                      colors: [rgb(255, 122, 89), rgb(226, 50, 56)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// 2) 白色日历卡片 + 阴影
let card = CGRect(x: 110, y: 110, width: 804, height: 804)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(120, 0, 0, 0.35))
ctx.addPath(roundedPath(card, 96))
ctx.setFillColor(rgb(255, 255, 255))
ctx.fillPath()
ctx.restoreGState()

// 3) 顶部红色 header（裁剪进卡片圆角）
ctx.saveGState()
ctx.addPath(roundedPath(card, 96))
ctx.clip()
let headerH: CGFloat = 210
ctx.setFillColor(rgb(226, 50, 56))
ctx.fill(CGRect(x: card.minX, y: card.maxY - headerH, width: card.width, height: headerH))
ctx.restoreGState()

// 4) 装订环
ctx.setFillColor(rgb(70, 70, 72))
for fx in [0.34, 0.66] {
    let x = card.minX + card.width * CGFloat(fx)
    ctx.addPath(roundedPath(CGRect(x: x - 18, y: card.maxY - 30, width: 36, height: 96), 18))
}
ctx.fillPath()

// 5) header 文字
drawText("北京时间", fontName: "PingFangSC-Semibold", size: 96,
         color: rgb(255, 255, 255), cx: card.midX, cy: card.maxY - headerH/2)

// 6) 主体大字「历」
drawText("历", fontName: "PingFangSC-Semibold", size: 360,
         color: rgb(226, 50, 56), cx: card.midX - 40, cy: card.minY + (card.height - headerH)/2 + 30)

// 7) 右下角时钟徽标
let clockC = CGPoint(x: 700, y: 285)
let R: CGFloat = 138
ctx.setFillColor(rgb(255, 255, 255))
ctx.addArc(center: clockC, radius: R, startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.fillPath()
ctx.setStrokeColor(rgb(226, 50, 56))
ctx.setLineWidth(16)
ctx.addArc(center: clockC, radius: R, startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.strokePath()
// 刻度
ctx.setFillColor(rgb(226, 50, 56))
for i in 0..<12 {
    let a = CGFloat(i) / 12 * .pi * 2
    let p = CGPoint(x: clockC.x + cos(a) * (R - 26), y: clockC.y + sin(a) * (R - 26))
    ctx.addArc(center: p, radius: 7, startAngle: 0, endAngle: .pi*2, clockwise: false)
    ctx.fillPath()
}
// 指针（10:10）
ctx.setStrokeColor(rgb(226, 50, 56))
ctx.setLineCap(.round)
ctx.setLineWidth(16)
ctx.move(to: clockC); ctx.addLine(to: CGPoint(x: clockC.x - 58, y: clockC.y + 56)); ctx.strokePath()
ctx.setLineWidth(13)
ctx.move(to: clockC); ctx.addLine(to: CGPoint(x: clockC.x + 50, y: clockC.y + 78)); ctx.strokePath()
ctx.setFillColor(rgb(226, 50, 56))
ctx.addArc(center: clockC, radius: 14, startAngle: 0, endAngle: .pi*2, clockwise: false)
ctx.fillPath()

// 输出 PNG
let img = ctx.makeImage()!
let url = URL(fileURLWithPath: "icon_1024.png")
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("icon_1024.png 已生成")
