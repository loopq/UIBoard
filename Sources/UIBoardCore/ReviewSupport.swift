import CoreGraphics
import Foundation

enum MarkdownRenderer {
    static func render(_ review: Review, created: Date, hits: [[ViewHit]]) -> String {
        let multi = review.frames.count > 1
        let sizes = review.frames.map(\.size)
        let board = BoardLayout.size(for: sizes)
        var lines = [
            "---",
            "format: uiboard-review/\(multi ? 2 : 1)",
            "created: \(timestamp(created))",
            "image: runtime.png",
            "size: \(integer(board.width))x\(integer(board.height))",
        ]
        if !multi { lines += factLines(review.facts, indent: "") }
        if !review.figmaURL.isEmpty { lines.append("figma: \(review.figmaURL)") }
        if !review.refs.isEmpty {
            let refs = review.refs.indices.map { "ref-\($0 + 1).png" }.joined(separator: ", ")
            lines.append("refs: [\(refs)]")
        }
        if multi {
            lines.append("frames:")
            for (index, (frame, offset)) in zip(review.frames, BoardLayout.offsets(for: sizes)).enumerated() {
                let label = Frame.label(at: index)
                lines += [
                    "  - frame: \(label)",
                    "    offset: \(integer(offset.x)),\(integer(offset.y))",
                    "    size: \(frame.image.width)x\(frame.image.height)",
                ]
                lines += factLines(frame.facts, indent: "    ")
                if frame.facts?.hierarchyXML != nil { lines.append("    hierarchy: hierarchy-\(label).xml") }
            }
        }
        lines += ["---", "", "# UI Review"]

        for (index, mark) in review.marks.enumerated() {
            let frame = review.frames[mark.frame]
            let crop = Crop.rect(for: mark, in: frame.size)
            lines += ["", "## #\(index + 1)", ""]
            if multi { lines.append("- frame: \(Frame.label(at: mark.frame))") }
            lines.append("- rect: \(integer(mark.rect.origin.x)),\(integer(mark.rect.origin.y)),\(integer(mark.rect.width)),\(integer(mark.rect.height))")
            if let density = frame.facts?.densityDpi {
                let scale = 160.0 / Double(density)
                lines.append("- dp: \(decimal(mark.rect.origin.x, scale: scale)),\(decimal(mark.rect.origin.y, scale: scale)),\(decimal(mark.rect.width, scale: scale)),\(decimal(mark.rect.height, scale: scale))")
            }
            lines.append("- crop: crops/\(index + 1).png @ \(integer(crop.origin.x)),\(integer(crop.origin.y))")
            if frame.facts != nil, index < hits.count, !hits[index].isEmpty {
                let value = hits[index].prefix(3).map(viewDescription).joined(separator: " · ")
                lines.append("- views: \(value)")
            }
            lines += ["", mark.note]
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func factLines(_ facts: DeviceFacts?, indent: String) -> [String] {
        guard let facts else { return [] }
        var lines = ["\(indent)source: adb"]
        let model = facts.model?
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usableModel = model.flatMap { $0.isEmpty ? nil : $0 }
        lines.append("\(indent)device: \(usableModel.map { "\($0) (\(facts.serial))" } ?? facts.serial)")
        if let density = facts.densityDpi { lines.append("\(indent)density: \(density)") }
        if let activity = facts.activity, !activity.isEmpty { lines.append("\(indent)activity: \(activity)") }
        return lines
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return formatter.string(from: date)
    }

    private static func integer(_ value: CGFloat) -> Int { Int(value.rounded()) }

    private static func decimal(_ value: CGFloat, scale: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(value) * scale)
    }

    private static func viewDescription(_ hit: ViewHit) -> String {
        let className = hit.className.split(separator: ".").last.map(String.init) ?? hit.className
        return "\(hit.resourceId) [\(className) \(integer(hit.bounds.origin.x)),\(integer(hit.bounds.origin.y)),\(integer(hit.bounds.width)),\(integer(hit.bounds.height))]"
    }
}

enum Exporter {
    static func export(_ review: Review, workspace: URL, now: Date) throws -> URL {
        let fileManager = FileManager.default
        let day = datePart(now, format: "yyyy-MM-dd")
        let time = datePart(now, format: "HH-mm-ss")
        let dayDirectory = workspace.appendingPathComponent(day, isDirectory: true)

        do {
            try fileManager.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
        } catch {
            throw UIBoardError.exportFailed(error.localizedDescription)
        }

        var suffix = 1
        var finalDirectory: URL
        var temporaryDirectory: URL
        repeat {
            let name = suffix == 1 ? time : "\(time)-\(suffix)"
            finalDirectory = dayDirectory.appendingPathComponent(name, isDirectory: true)
            temporaryDirectory = dayDirectory.appendingPathComponent(".\(name).tmp", isDirectory: true)
            suffix += 1
        } while fileManager.fileExists(atPath: finalDirectory.path)
            || fileManager.fileExists(atPath: temporaryDirectory.path)

        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
        } catch {
            throw UIBoardError.exportFailed(error.localizedDescription)
        }

        var completed = false
        defer {
            if !completed {
                try? fileManager.removeItem(at: temporaryDirectory)
            }
        }

        do {
            let multi = review.frames.count > 1
            let frames = review.frames
            guard
                let runtime = BoardComposer.compose(frames.map(\.image)),
                let annotated = BoardComposer.compose(try frames.indices.map { index in
                    guard let image = AnnotationDrawing.render(runtime: frames[index].image, marks: review.marks, frame: index, highlight: nil) else {
                        throw UIBoardError.imageEncodeFailed
                    }
                    return image
                })
            else {
                throw UIBoardError.imageEncodeFailed
            }
            try ImageCodec.png(runtime).write(to: temporaryDirectory.appendingPathComponent("runtime.png"))
            try ImageCodec.png(annotated).write(to: temporaryDirectory.appendingPathComponent("annotated.png"))

            let cropsDirectory = temporaryDirectory.appendingPathComponent("crops", isDirectory: true)
            try fileManager.createDirectory(at: cropsDirectory, withIntermediateDirectories: false)
            for (index, mark) in review.marks.enumerated() {
                let frame = frames[mark.frame]
                let rect = Crop.rect(for: mark, in: frame.size)
                guard !rect.isNull, !rect.isEmpty, let crop = frame.image.cropping(to: rect) else {
                    throw UIBoardError.exportFailed("Could not crop mark #\(index + 1).")
                }
                try ImageCodec.png(crop).write(to: cropsDirectory.appendingPathComponent("\(index + 1).png"))
            }

            for (index, reference) in review.refs.enumerated() {
                try ImageCodec.png(reference).write(to: temporaryDirectory.appendingPathComponent("ref-\(index + 1).png"))
            }

            for (index, frame) in frames.enumerated() {
                guard let hierarchy = frame.facts?.hierarchyXML else { continue }
                let name = multi ? "hierarchy-\(Frame.label(at: index)).xml" : "hierarchy.xml"
                try hierarchy.write(to: temporaryDirectory.appendingPathComponent(name))
            }
            let hits: [[ViewHit]] = review.marks.map { mark in
                frames[mark.frame].facts?.hierarchyXML.map { HierarchyHitTester.views(for: mark.rect, hierarchyXML: $0) } ?? []
            }
            let markdown = MarkdownRenderer.render(review, created: now, hits: hits)
            try Data(markdown.utf8).write(to: temporaryDirectory.appendingPathComponent("review.md"))

            try fileManager.moveItem(at: temporaryDirectory, to: finalDirectory)
            completed = true
            return finalDirectory
        } catch let error as UIBoardError {
            throw error
        } catch {
            throw UIBoardError.exportFailed(error.localizedDescription)
        }
    }

    private static func datePart(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
