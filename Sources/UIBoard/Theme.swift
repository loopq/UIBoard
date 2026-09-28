import AppKit
import SwiftUI

extension NSColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(rgb: UInt32) {
        self.init(nsColor: NSColor(rgb: rgb))
    }

    static let canvas = dynamic(NSColor(rgb: 0xECECEC), NSColor(rgb: 0x1E1E1E))
    static let panel = dynamic(NSColor(rgb: 0xF6F6F6), NSColor(rgb: 0x262626))
    static let card = dynamic(NSColor(rgb: 0xFFFFFF), NSColor(rgb: 0x2E2E2E))
    static let cardline = dynamic(NSColor(rgb: 0x000000, alpha: 0.08), NSColor(rgb: 0xFFFFFF, alpha: 0.07))
    static let selbg = dynamic(NSColor(rgb: 0xEAF3FF), NSColor(rgb: 0x0A84FF, alpha: 0.16))
    static let ctrl = dynamic(NSColor(rgb: 0x000000, alpha: 0.05), NSColor(rgb: 0xFFFFFF, alpha: 0.08))
    static let dash = dynamic(NSColor(rgb: 0x000000, alpha: 0.22), NSColor(rgb: 0xFFFFFF, alpha: 0.22))
    static let shotline = dynamic(NSColor(rgb: 0x000000, alpha: 0.12), NSColor(rgb: 0xFFFFFF, alpha: 0.14))

    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(Capsule().fill(Color.ctrl))
    }
}

extension URL {
    var tildePath: String { (path as NSString).abbreviatingWithTildeInPath }
}

func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}
