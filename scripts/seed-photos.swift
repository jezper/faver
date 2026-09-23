// Builds a small, entirely predictable photo library for the interface tests.
//
// Real photos with real capture dates and real coordinates, because the app groups by
// exactly those. Written as files here; loaded into the simulator by uitest.sh.
//
//   xcrun swift scripts/seed-photos.swift <output directory>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Shot {
    let name: String
    let offsetMinutes: Double
    let latitude: Double
    let longitude: Double
    let hue: CGFloat
}

/// Three moments, chosen so every rule the app has is exercised at least once:
/// a morning in one place, an afternoon far enough away to count as somewhere else,
/// and a different day entirely with a burst of three inside it.
func run(_ prefix: String, count: Int, from base: Double, step: Double,
         lat: Double, lon: Double, hue: CGFloat) -> [Shot] {
    (0..<count).map { i in
        Shot(
            name: "\(prefix)\(i)",
            offsetMinutes: base + Double(i) * step,
            latitude: lat,
            longitude: lon,
            hue: hue + CGFloat(i) * 0.04
        )
    }
}

let stockholmLat = 59.3293, stockholmLon = 18.0686
let uppsalaLat = 59.8586, uppsalaLon = 17.6389

let shots: [Shot] =
    run("morning", count: 4, from: 0, step: 3, lat: stockholmLat, lon: stockholmLon, hue: 0.05)
    + run("afternoon", count: 3, from: 300, step: 4, lat: uppsalaLat, lon: uppsalaLon, hue: 0.30)
    + run("nextday", count: 2, from: 1800, step: 5, lat: stockholmLat, lon: stockholmLon, hue: 0.60)
    + run("burst", count: 3, from: 1830, step: 1.0 / 120.0, lat: stockholmLat, lon: stockholmLon, hue: 0.80)

// Fixed point in the past so the same library comes out every run.
let start = Date(timeIntervalSince1970: 1_600_000_000)

let formatter = DateFormatter()
formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
formatter.timeZone = TimeZone(identifier: "UTC")

let dayFormatter = DateFormatter()
dayFormatter.dateFormat = "yyyy:MM:dd"
dayFormatter.timeZone = TimeZone(identifier: "UTC")

let timeFormatter = DateFormatter()
timeFormatter.dateFormat = "HH:mm:ss"
timeFormatter.timeZone = TimeZone(identifier: "UTC")

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: seed-photos.swift <output directory>\n".data(using: .utf8)!)
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func image(hue: CGFloat) -> CGImage? {
    let size = 1200
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    // A flat colour plus a band, so a person watching the test can tell them apart.
    context.setFillColor(red: hue, green: 0.4, blue: 1 - hue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(red: 1 - hue, green: 0.8, blue: hue, alpha: 1)
    context.fill(CGRect(x: 0, y: size / 3, width: size, height: size / 4))
    return context.makeImage()
}

for shot in shots {
    guard let cg = image(hue: shot.hue) else { continue }
    let taken = start.addingTimeInterval(shot.offsetMinutes * 60)
    let url = outputDirectory.appendingPathComponent("\(shot.name).jpg")

    let exif: [CFString: Any] = [
        kCGImagePropertyExifDateTimeOriginal: formatter.string(from: taken),
        kCGImagePropertyExifDateTimeDigitized: formatter.string(from: taken)
    ]
    let gps: [CFString: Any] = [
        kCGImagePropertyGPSLatitude: abs(shot.latitude),
        kCGImagePropertyGPSLatitudeRef: shot.latitude < 0 ? "S" : "N",
        kCGImagePropertyGPSLongitude: abs(shot.longitude),
        kCGImagePropertyGPSLongitudeRef: shot.longitude < 0 ? "W" : "E",
        kCGImagePropertyGPSDateStamp: dayFormatter.string(from: taken),
        kCGImagePropertyGPSTimeStamp: timeFormatter.string(from: taken)
    ]
    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: exif,
        kCGImagePropertyGPSDictionary: gps,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: formatter.string(from: taken)]
    ]

    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
    ) else { continue }
    CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
}

print("\(shots.count) photos written to \(outputDirectory.path)")
