// 生成 App 图标：Icon/AppIcon.icns（以及预览用的 Icon/AppIcon.png）
// 用法：swift Icon/make_icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let iconDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()

/// Draws the icon on a 1024-point canvas scaled to `size` pixels.
func renderIcon(size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: scale)

    // macOS icon grid: 824-pt body centered on the 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(srgbRed: 0.08, green: 0.33, blue: 0.84, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Body: blue gradient, lighter at the top.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(srgbRed: 0.24, green: 0.66, blue: 1.00, alpha: 1),
        CGColor(srgbRed: 0.07, green: 0.31, blue: 0.82, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Sonar rings fading outward from the center.
    let center = CGPoint(x: 512, y: 512)
    ctx.setLineWidth(42)
    for (radius, alpha) in [(150.0, 0.95), (250.0, 0.65), (350.0, 0.35)] {
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
        ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        ctx.strokePath()
    }

    // Center dot.
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: center.x - 62, y: center.y - 62, width: 124, height: 124))
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("无法写入 \(url.path)") }
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    writePNG(renderIcon(size: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    writePNG(renderIcon(size: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
writePNG(renderIcon(size: 1024), to: iconDir.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", iconDir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil 失败") }

try? FileManager.default.removeItem(at: iconset)
print("已生成：\(iconDir.appendingPathComponent("AppIcon.icns").path)")
