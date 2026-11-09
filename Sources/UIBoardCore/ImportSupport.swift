import CoreGraphics
import Foundation

/// The inverse of `Exporter`: review.md + runtime.png → `Review`. The input comes from other people's
/// machines, so every coordinate and file name is validated before it becomes a board.
/// v1 is read as v2 with a single frame "A" at 0,0 whose facts sit in the top-level frontmatter.
enum Importer {
    private struct Invalid: Error {
        let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    static func directories(in url: URL) -> [URL] {
        let fileManager = FileManager.default
        let children = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return ([url] + children.sorted { $0.path < $1.path })
            .filter { fileManager.fileExists(atPath: $0.appendingPathComponent("review.md").path) }
    }

    static func load(_ directory: URL) throws -> Review {
        do {
            return try parse(directory)
        } catch let invalid as Invalid {
            throw UIBoardError.importFailed("\(directory.lastPathComponent): \(invalid.reason)")
        }
    }

    private static func parse(_ directory: URL) throws -> Review {
        guard let text = String(data: try file("review.md", in: directory), encoding: .utf8) else {
            throw Invalid("review.md is not UTF-8 text")
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
            throw Invalid("review.md has no frontmatter")
        }
        let (fields, frameFields) = frontmatter(lines[1..<end])
        let runtime = try image("runtime.png", in: directory)

        let specs: [[String: String]]
        switch fields["format"] {
        case "uiboard-review/1":
            var single = fields.merging(["frame": "A", "offset": "0,0"]) { $1 }
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("hierarchy.xml").path) {
                single["hierarchy"] = "hierarchy.xml"
            }
            specs = [single]
        case "uiboard-review/2":
            specs = frameFields
        default:
            throw Invalid("unsupported format “\(fields["format"] ?? "")”")
        }
        guard !specs.isEmpty else { throw Invalid("review.md lists no frames") }

        let bounds = CGRect(x: 0, y: 0, width: runtime.width, height: runtime.height)
        var labels: [String: Int] = [:]
        let frames = try specs.enumerated().map { index, spec -> Frame in
            let label = spec["frame"] ?? ""
            let offset = try numbers(spec["offset"], separator: ",", count: 2, what: "offset of frame \(label)")
            let size = try numbers(spec["size"], separator: "x", count: 2, what: "size of frame \(label)")
            let rect = CGRect(x: offset[0], y: offset[1], width: size[0], height: size[1])
            guard rect.width > 0, rect.height > 0, bounds.contains(rect), let image = runtime.cropping(to: rect) else {
                throw Invalid("frame \(label) lies outside runtime.png")
            }
            guard labels.updateValue(index, forKey: label) == nil else { throw Invalid("frame \(label) is listed twice") }
            return Frame(image: image, facts: try facts(spec, in: directory))
        }

        let marks = try sections(lines[(end + 1)...]).enumerated().map { index, section -> Mark in
            let number = index + 1
            let label = section.fields["frame"] ?? (frames.count == 1 ? specs[0]["frame"] : nil) ?? ""
            guard let frame = labels[label] else { throw Invalid("#\(number) points at unknown frame “\(label)”") }
            let r = try numbers(section.fields["rect"], separator: ",", count: 4, what: "rect of #\(number)")
            let rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
            let size = frames[frame].size
            guard r.allSatisfy({ $0 >= 0 }), rect.maxX <= size.width, rect.maxY <= size.height else {
                throw Invalid("#\(number) lies outside frame \(label)")
            }
            return Mark(rect: rect, note: section.note, frame: frame)
        }

        let refs = try (fields["refs"] ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .split(separator: ",")
            .map { try image(trimmed($0), in: directory) }

        return Review(frames: frames, marks: marks, refs: refs, figmaURL: fields["figma"] ?? "")
    }

    /// Top-level `key: value` lines, plus one dictionary per `  - ` item under `frames:`.
    private static func frontmatter(_ lines: ArraySlice<String>) -> ([String: String], [[String: String]]) {
        var fields: [String: String] = [:]
        var frames: [[String: String]] = []
        for line in lines {
            if line.hasPrefix("  - ") {
                frames.append([:])
            }
            guard let (key, value) = pair(line.drop { $0 == " " || $0 == "-" }) else { continue }
            if line.hasPrefix("  "), !frames.isEmpty {
                frames[frames.count - 1][key] = value
            } else {
                fields[key] = value
            }
        }
        return (fields, frames)
    }

    /// Each `## #N` section: bullet lines up to the first blank line, then the note.
    private static func sections(_ lines: ArraySlice<String>) -> [(fields: [String: String], note: String)] {
        var sections: [[String]] = []
        for line in lines {
            if line.hasPrefix("## #"), line.count > 4, line.dropFirst(4).allSatisfy({ ("0"..."9").contains($0) }) {
                sections.append([])
            } else if !sections.isEmpty {
                sections[sections.count - 1].append(line)
            }
        }
        return sections.map { lines in
            let content = lines.drop(while: \.isEmpty)
            let bullets = content.prefix { !$0.isEmpty }
            var fields: [String: String] = [:]
            for bullet in bullets where bullet.hasPrefix("- ") {
                if let (key, value) = pair(bullet.dropFirst(2)) { fields[key] = value }
            }
            let note = content.dropFirst(bullets.count).joined(separator: "\n")
            return (fields, note.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func facts(_ spec: [String: String], in directory: URL) throws -> DeviceFacts? {
        guard spec["source"] == "adb" else { return nil }
        // "MI 9 (6e9b5937)" or just the serial; see MarkdownRenderer.factLines.
        let device = spec["device"] ?? ""
        var model: String?
        var serial = device
        if device.hasSuffix(")"), let open = device.range(of: " (", options: .backwards) {
            model = String(device[..<open.lowerBound])
            serial = String(device[open.upperBound..<device.index(before: device.endIndex)])
        }
        let density = try spec["density"].map { value -> Int in
            guard let density = Int(value), density > 0 else { throw Invalid("density “\(value)” is not a number") }
            return density
        }
        return DeviceFacts(serial: serial, model: model, densityDpi: density, activity: spec["activity"],
                           hierarchyXML: try spec["hierarchy"].map { try file($0, in: directory) })
    }

    private static func numbers(_ value: String?, separator: Character, count: Int, what: String) throws -> [CGFloat] {
        let raw = (value ?? "").split(separator: separator, omittingEmptySubsequences: false)
        let parts = raw.compactMap { Double(trimmed($0)) }.filter(\.isFinite)
        guard raw.count == count, parts.count == count else { throw Invalid("\(what) is malformed") }
        return parts.map { CGFloat($0) }
    }

    /// Only plain names inside the review directory: never follow `../` from someone else's review.md.
    private static func file(_ name: String, in directory: URL) throws -> Data {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { throw Invalid("refuses file name “\(name)”") }
        guard let data = FileManager.default.contents(atPath: directory.appendingPathComponent(name).path) else {
            throw Invalid("\(name) is missing")
        }
        return data
    }

    private static func image(_ name: String, in directory: URL) throws -> CGImage {
        guard let image = try? ImageCodec.decode(try file(name, in: directory)) else {
            throw Invalid("\(name) is missing or not an image")
        }
        return image
    }

    private static func pair(_ line: Substring) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        return (trimmed(line[..<colon]), trimmed(line[line.index(after: colon)...]))
    }

    private static func trimmed(_ value: Substring) -> String {
        value.trimmingCharacters(in: .whitespaces)
    }
}
