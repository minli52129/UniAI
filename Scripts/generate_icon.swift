// 生成应用图标（1024x1024 PNG）。用法：swift Scripts/generate_icon.swift build/icon_1024.png
// CI 中随后用 sips 缩放 + iconutil 打包成 AppIcon.icns。
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let side: CGFloat = 1024

let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

let inset: CGFloat = 64
let radius: CGFloat = 200
let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

if let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.28, green: 0.32, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.95, green: 0.42, blue: 0.62, alpha: 1)
]) {
    gradient.draw(in: shape, angle: -70)
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 430, weight: .heavy),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
let text = NSAttributedString(string: "AI", attributes: attributes)
let textSize = text.size()
text.draw(in: NSRect(x: 0, y: (side - textSize.height) / 2 - 30, width: side, height: textSize.height))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("生成图标失败\n", stderr)
    exit(1)
}

do {
    let outputURL = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL)
    print("已生成图标: \(output)")
} catch {
    fputs("写出图标失败: \(error)\n", stderr)
    exit(1)
}
