#!/usr/bin/env swift

import AppKit
import Foundation

struct Slide {
    let filename: String
    let title: String
    let subtitle: String
    let screenshot: String
    let titleSize: CGFloat
}

let slides: [Slide] = [
    Slide(
        filename: "01-know-what-to-run-today.png",
        title: "Know What to\nRun Today",
        subtitle: "A clear, personalized workout—ready when you are.",
        screenshot: "01-today-light.png",
        titleSize: 100
    ),
    Slide(
        filename: "02-training-plan-adapts.png",
        title: "A Training Plan\nThat Adapts to You",
        subtitle: "Built from your plan, recent training, readiness, and preferences.",
        screenshot: "07-ai-planned-workout-light.png",
        titleSize: 88
    ),
    Slide(
        filename: "03-real-time-coaching.png",
        title: "Real-Time Coaching\nThrough Every Interval",
        subtitle: "Stay on pace with guidance that follows the run in front of you.",
        screenshot: "03-live-redmond-half-light.png",
        titleSize: 82
    ),
    Slide(
        filename: "04-adjust-around-real-life.png",
        title: "Adjust Any Workout\nAround Real Life",
        subtitle: "Ask for a useful change while keeping the purpose of the workout.",
        screenshot: "07-ai-planned-workout-light.png",
        titleSize: 88
    ),
    Slide(
        filename: "05-share-live-with-trusted-people.png",
        title: "Share Your Run Live\nwith People You Trust",
        subtitle: "You choose who can follow your location and live run stats.",
        screenshot: "05-cheer-live-track-dark.png",
        titleSize: 84
    ),
    Slide(
        filename: "06-hear-cheers-while-running.png",
        title: "Hear Your Family and Friends\nCheer You On While You Run",
        subtitle: "Friends and family can send short voice cheers while you’re moving.",
        screenshot: "06-live-cheer-follower-light.png",
        titleSize: 72
    ),
    Slide(
        filename: "07-plan-and-guide-your-race.png",
        title: "Intelligently Plan and\nGuide Your Race",
        subtitle: "Recent training becomes a patient pacing plan built for race day.",
        screenshot: "17-race-planning-light.png",
        titleSize: 88
    ),
    Slide(
        filename: "08-community-routes.png",
        title: "Find and Follow\nCommunity Routes",
        subtitle: "Discover a route, stay on course, and see your progress as you run.",
        screenshot: "08-community-routes-redmond-light.png",
        titleSize: 90
    ),
    Slide(
        filename: "09-run-together.png",
        title: "Run Together with\nFriends and Groups",
        subtitle: "Build consistency with shared goals, activities, and encouragement.",
        screenshot: "18-circle-detail-progress-light.png",
        titleSize: 88
    ),
    Slide(
        filename: "10-everything-on-start-screen.png",
        title: "Everything Ready\non One Start Screen",
        subtitle: "Workout, route, guidance, music, safety, and gear—ready to go.",
        screenshot: "01-today-light.png",
        titleSize: 88
    ),
    Slide(
        filename: "11-remember-every-run.png",
        title: "Remember Every Run\nBeyond the Finish Line",
        subtitle: "Revisit the route, stats, and moments that made the run yours.",
        screenshot: "10-activity-detail-photos-light.png",
        titleSize: 84
    ),
]

let fileManager = FileManager.default
let repositoryRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let sourceDirectory = repositoryRoot.appendingPathComponent("artifacts/app-store-screenshots")
let outputDirectory = sourceDirectory.appendingPathComponent("framed-light")
let backgroundURL = outputDirectory.appendingPathComponent("background-route-ivory.png")

guard fileManager.fileExists(atPath: backgroundURL.path) else {
    fputs("Missing background: \(backgroundURL.path)\n", stderr)
    exit(1)
}

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let canvasWidth = 1284
let canvasHeight = 2778
let canvasSize = NSSize(width: canvasWidth, height: canvasHeight)

let ink = NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.085, alpha: 1)
let secondaryInk = NSColor(calibratedRed: 0.31, green: 0.29, blue: 0.25, alpha: 1)
let gold = NSColor(calibratedRed: 0.86, green: 0.49, blue: 0.00, alpha: 1)
let deepGreen = NSColor(calibratedRed: 0.015, green: 0.23, blue: 0.18, alpha: 1)

func rectFromTop(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(canvasHeight) - top - height, width: width, height: height)
}

func aspectFill(_ image: NSImage, in destination: NSRect) {
    let sourceSize = image.size
    let destinationAspect = destination.width / destination.height
    let sourceAspect = sourceSize.width / sourceSize.height
    let sourceRect: NSRect

    if sourceAspect > destinationAspect {
        let sourceWidth = sourceSize.height * destinationAspect
        sourceRect = NSRect(
            x: (sourceSize.width - sourceWidth) / 2,
            y: 0,
            width: sourceWidth,
            height: sourceSize.height
        )
    } else {
        let sourceHeight = sourceSize.width / destinationAspect
        sourceRect = NSRect(
            x: 0,
            y: (sourceSize.height - sourceHeight) / 2,
            width: sourceSize.width,
            height: sourceHeight
        )
    }

    image.draw(in: destination, from: sourceRect, operation: .sourceOver, fraction: 1)
}

func drawText(
    _ text: String,
    in rect: NSRect,
    font: NSFont,
    color: NSColor,
    lineSpacing: CGFloat = 0,
    alignment: NSTextAlignment = .left,
    kern: CGFloat = 0
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = lineSpacing
    paragraph.maximumLineHeight = font.pointSize * 1.08
    paragraph.minimumLineHeight = font.pointSize * 1.03

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: kern,
    ]
    NSAttributedString(string: text, attributes: attributes).draw(in: rect)
}

func drawRoundedImage(_ screenshot: NSImage, top: CGFloat) {
    let outerRect = rectFromTop(x: 167, top: top, width: 950, height: 2020)
    let screenRect = outerRect.insetBy(dx: 15, dy: 15)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 46
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: outerRect, xRadius: 96, yRadius: 96).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screenRect, xRadius: 82, yRadius: 82).addClip()
    aspectFill(screenshot, in: screenRect)
    NSGraphicsContext.restoreGraphicsState()

    gold.withAlphaComponent(0.64).setStroke()
    let border = NSBezierPath(roundedRect: outerRect.insetBy(dx: 4, dy: 4), xRadius: 92, yRadius: 92)
    border.lineWidth = 6
    border.stroke()
}

func render(slide: Slide, index: Int, background: NSImage) throws {
    guard let screenshot = NSImage(contentsOf: sourceDirectory.appendingPathComponent(slide.screenshot)) else {
        throw NSError(domain: "PlainstrideScreenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing screenshot: \(slide.screenshot)"])
    }

    guard let cgContext = CGContext(
        data: nil,
        width: canvasWidth,
        height: canvasHeight,
        bitsPerComponent: 8,
        bytesPerRow: canvasWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw NSError(domain: "PlainstrideScreenshots", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create output canvas"])
    }
    let graphics = NSGraphicsContext(cgContext: cgContext, flipped: false)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high

    NSColor(calibratedRed: 0.98, green: 0.965, blue: 0.925, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
    aspectFill(background, in: NSRect(origin: .zero, size: canvasSize))
    NSColor.white.withAlphaComponent(0.14).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

    let markRect = rectFromTop(x: 92, top: 88, width: 56, height: 56)
    deepGreen.setFill()
    NSBezierPath(roundedRect: markRect, xRadius: 17, yRadius: 17).fill()
    drawText("✦", in: rectFromTop(x: 97, top: 91, width: 46, height: 48), font: NSFont.systemFont(ofSize: 34, weight: .semibold), color: NSColor(calibratedRed: 1, green: 0.74, blue: 0.20, alpha: 1), alignment: .center)
    drawText("PLAINSTRIDE", in: rectFromTop(x: 169, top: 96, width: 420, height: 42), font: NSFont.systemFont(ofSize: 30, weight: .semibold), color: deepGreen, kern: 5.4)

    let counterRect = rectFromTop(x: 1050, top: 88, width: 142, height: 58)
    NSColor.white.withAlphaComponent(0.74).setFill()
    NSBezierPath(roundedRect: counterRect, xRadius: 29, yRadius: 29).fill()
    let counterText = index <= 10 ? String(format: "%02d / 10", index) : "ALT"
    drawText(counterText, in: rectFromTop(x: 1050, top: 100, width: 142, height: 36), font: NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .medium), color: secondaryInk, alignment: .center, kern: 1)

    drawText(slide.title, in: rectFromTop(x: 92, top: 218, width: 1096, height: 250), font: NSFont.systemFont(ofSize: slide.titleSize, weight: .bold), color: ink, lineSpacing: 2, kern: -1.8)
    drawText(slide.subtitle, in: rectFromTop(x: 96, top: 512, width: 1088, height: 116), font: NSFont.systemFont(ofSize: 38, weight: .regular), color: secondaryInk, lineSpacing: 7, kern: -0.2)

    gold.setFill()
    NSBezierPath(roundedRect: rectFromTop(x: 96, top: 684, width: 118, height: 9), xRadius: 4.5, yRadius: 4.5).fill()
    NSColor(calibratedWhite: 0.2, alpha: 0.14).setFill()
    NSBezierPath(roundedRect: rectFromTop(x: 226, top: 684, width: 962, height: 9), xRadius: 4.5, yRadius: 4.5).fill()

    drawRoundedImage(screenshot, top: 720)

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = cgContext.makeImage() else {
        throw NSError(domain: "PlainstrideScreenshots", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to finalize output canvas"])
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 1]) else {
        throw NSError(domain: "PlainstrideScreenshots", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }
    try data.write(to: outputDirectory.appendingPathComponent(slide.filename), options: .atomic)
}

guard let background = NSImage(contentsOf: backgroundURL) else {
    fputs("Unable to read background: \(backgroundURL.path)\n", stderr)
    exit(1)
}

do {
    for (offset, slide) in slides.enumerated() {
        try render(slide: slide, index: offset + 1, background: background)
        print("Rendered \(slide.filename)")
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
