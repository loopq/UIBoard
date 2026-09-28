import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageCodec {
    static func decode(_ data: Data) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw UIBoardError.imageDecodeFailed
        }
        return image
    }

    static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw UIBoardError.imageEncodeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw UIBoardError.imageEncodeFailed
        }
        return data as Data
    }
}

enum BoardComposer {
    static let gapColor: UInt32 = 0xE5E5EA

    static func compose(_ images: [CGImage]) -> CGImage? {
        if images.count == 1 { return images[0] }
        let sizes = images.map { CGSize(width: $0.width, height: $0.height) }
        let board = BoardLayout.size(for: sizes)
        guard let context = CGContext(
            data: nil,
            width: Int(board.width),
            height: Int(board.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(AnnotationDrawing.cgColor(gapColor))
        context.fill(CGRect(origin: .zero, size: board))
        for (image, offset) in zip(images, BoardLayout.offsets(for: sizes)) {
            let flippedY = board.height - offset.y - CGFloat(image.height)
            context.draw(image, in: CGRect(x: offset.x, y: flippedY, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        return context.makeImage()
    }
}

enum AnnotationDrawing {
    static func render(runtime: CGImage, marks: [Mark], frame: Int = 0, highlight: Int?) -> CGImage? {
        let width = runtime.width
        let height = runtime.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(runtime, in: imageBounds)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let baseLineWidth = max(3, round(CGFloat(width) * 0.004))
        let badgeDiameter = round(CGFloat(width) * 0.05)
        let pinRadius = round(CGFloat(width) * 0.012)
        let pinOffset = round(CGFloat(width) * 0.089)
        let fontSize = round(badgeDiameter * 0.52)

        for (index, mark) in marks.enumerated() where mark.frame == frame {
            let color = cgColor(Palette.rgb(at: index))
            let markLineWidth = highlight == index ? baseLineWidth * 2 : baseLineWidth
            let desiredBadgeCenter: CGPoint

            context.setStrokeColor(color)
            context.setLineWidth(markLineWidth)

            if mark.isPin {
                let pinCenter = mark.rect.origin
                desiredBadgeCenter = CGPoint(x: pinCenter.x + pinOffset, y: pinCenter.y - pinOffset)
                let badgeCenter = clamp(
                    desiredBadgeCenter,
                    diameter: badgeDiameter,
                    width: CGFloat(width),
                    height: CGFloat(height)
                )
                drawLeader(
                    in: context,
                    from: pinCenter,
                    pinRadius: pinRadius,
                    to: badgeCenter,
                    badgeRadius: badgeDiameter / 2,
                    color: color,
                    lineWidth: highlight == index
                        ? max(2, round(baseLineWidth * 0.75)) * 2
                        : max(2, round(baseLineWidth * 0.75))
                )
                context.strokeEllipse(in: CGRect(
                    x: pinCenter.x - pinRadius,
                    y: pinCenter.y - pinRadius,
                    width: pinRadius * 2,
                    height: pinRadius * 2
                ))
                drawBadge(
                    in: context,
                    center: badgeCenter,
                    diameter: badgeDiameter,
                    lineWidth: baseLineWidth,
                    color: color,
                    number: index + 1,
                    fontSize: fontSize
                )
            } else {
                desiredBadgeCenter = mark.rect.origin
                context.stroke(mark.rect)
                drawBadge(
                    in: context,
                    center: clamp(
                        desiredBadgeCenter,
                        diameter: badgeDiameter,
                        width: CGFloat(width),
                        height: CGFloat(height)
                    ),
                    diameter: badgeDiameter,
                    lineWidth: baseLineWidth,
                    color: color,
                    number: index + 1,
                    fontSize: fontSize
                )
            }
        }

        return context.makeImage()
    }

    static func cgColor(_ rgb: UInt32) -> CGColor {
        CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [
                CGFloat((rgb >> 16) & 0xFF) / 255,
                CGFloat((rgb >> 8) & 0xFF) / 255,
                CGFloat(rgb & 0xFF) / 255,
                1,
            ]
        )!
    }

    private static func clamp(_ point: CGPoint, diameter: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        let radius = diameter / 2
        return CGPoint(
            x: min(max(point.x, radius), width - radius),
            y: min(max(point.y, radius), height - radius)
        )
    }

    private static func drawLeader(
        in context: CGContext,
        from pin: CGPoint,
        pinRadius: CGFloat,
        to badge: CGPoint,
        badgeRadius: CGFloat,
        color: CGColor,
        lineWidth: CGFloat
    ) {
        let dx = badge.x - pin.x
        let dy = badge.y - pin.y
        let distance = hypot(dx, dy)
        guard distance > pinRadius + badgeRadius else { return }
        let unit = CGPoint(x: dx / distance, y: dy / distance)
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.move(to: CGPoint(x: pin.x + unit.x * pinRadius, y: pin.y + unit.y * pinRadius))
        context.addLine(to: CGPoint(x: badge.x - unit.x * badgeRadius, y: badge.y - unit.y * badgeRadius))
        context.strokePath()
        context.restoreGState()
    }

    private static func drawBadge(
        in context: CGContext,
        center: CGPoint,
        diameter: CGFloat,
        lineWidth: CGFloat,
        color: CGColor,
        number: Int,
        fontSize: CGFloat
    ) {
        let rect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        context.saveGState()
        context.setFillColor(color)
        context.fillEllipse(in: rect)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: rect)

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(number), attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(
            x: center.x - bounds.midX,
            y: center.y + bounds.midY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
