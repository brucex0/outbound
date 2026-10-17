#!/usr/bin/env swift
import AppKit
import Foundation

// Compose existing captures without changing their contents or aspect ratio.
// Usage: swift scripts/generate-app-store-creative.swift <repo-with-artifacts> <output>
let args = CommandLine.arguments
let root = URL(fileURLWithPath: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath)
let output = URL(fileURLWithPath: args.count > 2 ? args[2] : root.appendingPathComponent("artifacts/app-store-creative").path)
let fm = FileManager.default
let green = NSColor(srgbRed: 0.025, green: 0.23, blue: 0.18, alpha: 1)
let ivory = NSColor(srgbRed: 0.98, green: 0.965, blue: 0.925, alpha: 1)
let gold = NSColor(srgbRed: 0.86, green: 0.49, blue: 0, alpha: 1)
let muted = NSColor(srgbRed: 0.34, green: 0.38, blue: 0.34, alpha: 1)
struct Copy {
    let locale: String
    let header: String
    let search: String
    let titles: [String]
    let subtitles: [String]
}
let copies = [
    Copy(locale: "en-US", header: "A running plan that\nmoves with life.", search: "Your next run,\nfigured out.", titles: ["Know what to\nrun today.", "A plan that\nadapts with you.", "See your\nprogress add up."], subtitles: ["A clear workout. A little less guesswork.", "Understand today’s run. Find your next adjustment.", "Your best efforts and personal records, together."]),
    Copy(locale: "es", header: "Un plan de running\nal ritmo de tu vida.", search: "Tu próxima carrera,\nsin darle vueltas.", titles: ["Ten claro qué\ncorrer hoy.", "Un plan que\nse adapta a ti.", "Mira cuánto\nhas avanzado."], subtitles: ["Un entrenamiento claro. Menos dudas al salir.", "Entiende tu entrenamiento y cómo ajustarlo.", "Tus mejores marcas, en un solo lugar."]),
    Copy(locale: "zh-Hans", header: "跑步有计划，\n生活有余地。", search: "下一次怎么跑，\n心里有数。", titles: ["今天怎么跑，\n一看就知道。", "计划随你调整，\n跑步从容安排。", "每一点进步，\n都看得见。"], subtitles: ["训练安排清晰，出发少些犹豫。", "了解今天的训练，找到适合自己的调整。", "最佳表现与个人纪录，一目了然。"])
]
func load(_ path: String) throws -> NSImage {
    let url = root.appendingPathComponent(path)
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(domain: "AppStoreCreative", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read source asset: \(url.path)"])
    }
    return image
}
func box(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x, y: height - top - h, width: w, height: h)
}
func text(_ value: String, _ rect: NSRect, _ size: CGFloat, _ color: NSColor, _ weight: NSFont.Weight = .bold) throws {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = size * 0.08
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph]
    let string = NSAttributedString(string: value, attributes: attributes)
    let measured = string.boundingRect(with: NSSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
    guard measured.height <= rect.height + 1 else {
        throw NSError(domain: "AppStoreCreative", code: 2, userInfo: [NSLocalizedDescriptionKey: "Text exceeds available height: \(value)"])
    }
    string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}
func image(_ source: NSImage, _ rect: NSRect, fill: Bool = false) {
    let ratio = fill ? max(rect.width / source.size.width, rect.height / source.size.height) : min(rect.width / source.size.width, rect.height / source.size.height)
    let size = NSSize(width: source.size.width * ratio, height: source.size.height * ratio)
    let target = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: rect).addClip()
    source.draw(in: target)
    NSGraphicsContext.restoreGraphicsState()
}
func render(_ name: String, _ width: Int, _ height: Int, _ draw: (CGFloat, CGFloat) throws -> Void) throws {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw NSError(domain: "AppStoreCreative", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot create canvas: \(name)"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current?.imageInterpolation = .high
    ivory.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    try draw(CGFloat(width), CGFloat(height))
    NSGraphicsContext.restoreGraphicsState()
    guard let result = context.makeImage(), let data = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AppStoreCreative", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot encode canvas: \(name)"])
    }
    let url = output.appendingPathComponent(name)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    print("Rendered \(name)")
}
func brand(_ icon: NSImage, _ x: CGFloat, _ top: CGFloat, _ size: CGFloat, _ height: CGFloat, light: Bool = false) throws {
    image(icon, box(x, top, size, size, height))
    try text("Plainstride", box(x + size * 1.3, top + size * 0.12, size * 6.8, size, height), size * 0.64, light ? ivory : green, .semibold)
}
do {
    let icon = try load("ios/Outbound/Outbound/Assets.xcassets/AppIcon.appiconset/OutboundFoxAppIcon.png")
    let photo = try load("backend/src/scripts/assets/running-photos/coastal-trail.jpg")
    let screens = try ["01-today-light.png", "07-ai-planned-workout-light.png", "19-progress-records-light.png"].map { try load("artifacts/app-store-screenshots/" + $0) }
    for copy in copies {
        try render("\(copy.locale)/header.png", 3840, 1646) { w, h in
            green.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: h)).fill()
            image(photo, box(2050, 0, 1790, h, h), fill: true)
            try brand(icon, 420, 330, 106, h, light: true)
            try text(copy.header, box(420, 580, 1780, 560, h), copy.locale == "es" ? 150 : 168, ivory)
            gold.setFill(); NSBezierPath(roundedRect: box(420, 1210, 180, 14, h), xRadius: 7, yRadius: 7).fill()
        }
        try render("\(copy.locale)/search.png", 1920, 1280) { _, h in
            try brand(icon, 150, 240, 72, h)
            try text(copy.search, box(150, 430, 940, 440, h), copy.locale == "es" ? 96 : 114, green)
            gold.setFill(); NSBezierPath(roundedRect: box(150, 930, 130, 10, h), xRadius: 5, yRadius: 5).fill()
            image(screens[0], box(1170, 100, 500, 1082, h))
        }
        for index in 0..<3 {
            try render("\(copy.locale)/0\(index + 1)-screenshot.png", 1284, 2778) { _, h in
                try brand(icon, 110, 100, 66, h)
                try text(copy.titles[index], box(110, 270, 1064, 310, h), copy.locale == "es" ? 94 : 106, green)
                try text(copy.subtitles[index], box(114, 590, 1056, 145, h), 39, muted, .regular)
                gold.setFill(); NSBezierPath(roundedRect: box(114, 777, 130, 10, h), xRadius: 5, yRadius: 5).fill()
                image(screens[index], box(207, 850, 870, 1882.3, h))
            }
        }
    }
    try render("review-sheet.png", 1800, 2400) { _, h in
        for (column, copy) in copies.enumerated() {
            let x = CGFloat(column * 600)
            try text(copy.locale, box(x + 30, 20, 540, 50, h), 28, green)
            for (row, filename) in ["header.png", "search.png", "01-screenshot.png", "02-screenshot.png", "03-screenshot.png"].enumerated() {
                let url = output.appendingPathComponent(copy.locale).appendingPathComponent(filename)
                guard let asset = NSImage(contentsOf: url) else {
                    throw NSError(domain: "AppStoreCreative", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cannot read rendered asset: \(url.path)"])
                }
                image(asset, box(x + 20, CGFloat(80 + row * 460), 560, 440, h))
            }
        }
    }
} catch {
    fputs("App Store creative generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
