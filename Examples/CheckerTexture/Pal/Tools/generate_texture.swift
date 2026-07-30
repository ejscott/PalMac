import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate_texture.swift OUTPUT.png\n".utf8))
    exit(64)
}

let width = 1024
let height = 1024
let tile = 128
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: width * 4,
    bitsPerPixel: 32
) else {
    exit(1)
}

let cyan = NSColor(calibratedRed: 0, green: 0.95, blue: 1, alpha: 1)
let magenta = NSColor(calibratedRed: 1, green: 0, blue: 0.75, alpha: 1)
let yellow = NSColor(calibratedRed: 1, green: 0.95, blue: 0, alpha: 1)
let black = NSColor(calibratedWhite: 0.02, alpha: 1)

for y in 0..<height {
    for x in 0..<width {
        let border = x % tile < 10 || y % tile < 10
        let diagonal = abs((x % tile) - (y % tile)) < 8
        let checker = ((x / tile) + (y / tile)) % 2 == 0
        bitmap.setColor(
            border ? black : (diagonal ? yellow : (checker ? cyan : magenta)),
            atX: x,
            y: y
        )
    }
}

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: output, options: .atomic)
