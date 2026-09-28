import CoreGraphics
import Foundation
import XCTest
@testable import UIBoardCore

func solidImage(width: Int, height: Int, rgb: UInt32 = 0x336699) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [
            CGFloat((rgb >> 16) & 0xFF) / 255,
            CGFloat((rgb >> 8) & 0xFF) / 255,
            CGFloat(rgb & 0xFF) / 255,
            1,
        ]
    )!)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

func fixture(_ name: String, extension ext: String, subdirectory: String? = nil) throws -> Data {
    let directory = subdirectory.map { "Fixtures/\($0)" } ?? "Fixtures"
    return try Data(contentsOf: XCTUnwrap(
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: directory)
    ))
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("UIBoardTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}
