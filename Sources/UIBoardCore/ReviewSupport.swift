import CoreGraphics
import Foundation

enum MarkdownRenderer {
    static func render(_ review: Review, created: Date, hits: [[ViewHit]]) -> String {
        var lines = [
            "---",
            "format: uiboard-review/1",
            "created: \(timestamp(created))",
            "image: runtime.png",
            "size: \(review.runtime.width)x\(review.runtime.height)",
        ]

        if let facts = review.facts {
            lines.append("source: adb")
            let model = facts.model?
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let usableModel = model.flatMap { $0.isEmpty ? nil : $0 }
            lines.append("device: \(usableModel.map { "\($0) (\(facts.serial))" } ?? facts.serial)")
            if let density = facts.densityDpi { lines.append("density: \(density)") }
            if let activity = facts.activity, !activity.isEmpty { lines.append("activity: \(activity)") }
        }
        if !review.figmaURL.isEmpty { lines.append("figma: \(review.figmaURL)") }
        if !review.refs.isEmpty {
            let refs = review.refs.indices.map { "ref-\($0 + 1).png" }.joined(separator: ", ")
            lines.append("refs: [\(refs)]")
        }
        lines += ["---", "", "# UI Review"]

        for (index, mark) in review.marks.enumerated() {
            let crop = Crop.rect(for: mark, in: review.pixelSize)
            lines += [
                "",
                "## #\(index + 1)",
                "",
                "- rect: \(integer(mark.rect.origin.x)),\(integer(mark.rect.origin.y)),\(integer(mark.rect.width)),\(integer(mark.rect.height))",
            ]
            if let density = review.facts?.densityDpi {
                let scale = 160.0 / Double(density)
                lines.append("- dp: \(decimal(mark.rect.origin.x, scale: scale)),\(decimal(mark.rect.origin.y, scale: scale)),\(decimal(mark.rect.width, scale: scale)),\(decimal(mark.rect.height, scale: scale))")
            }
            lines.append("- crop: crops/\(index + 1).png @ \(integer(crop.origin.x)),\(integer(crop.origin.y))")
            if review.facts != nil, index < hits.count, !hits[index].isEmpty {
                let value = hits[index].prefix(3).map(viewDescription).joined(separator: " · ")
                lines.append("- views: \(value)")
            }
            lines += ["", mark.note]
        }

        return lines.joined(separator: "\n") + "\n"
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
            try ImageCodec.png(review.runtime).write(to: temporaryDirectory.appendingPathComponent("runtime.png"))
            guard let annotated = AnnotationDrawing.render(runtime: review.runtime, marks: review.marks, highlight: nil) else {
                throw UIBoardError.imageEncodeFailed
            }
            try ImageCodec.png(annotated).write(to: temporaryDirectory.appendingPathComponent("annotated.png"))

            let cropsDirectory = temporaryDirectory.appendingPathComponent("crops", isDirectory: true)
            try fileManager.createDirectory(at: cropsDirectory, withIntermediateDirectories: false)
            for (index, mark) in review.marks.enumerated() {
                let rect = Crop.rect(for: mark, in: review.pixelSize)
                guard !rect.isNull, !rect.isEmpty, let crop = review.runtime.cropping(to: rect) else {
                    throw UIBoardError.exportFailed("Could not crop mark #\(index + 1).")
                }
                try ImageCodec.png(crop).write(to: cropsDirectory.appendingPathComponent("\(index + 1).png"))
            }

            for (index, reference) in review.refs.enumerated() {
                try ImageCodec.png(reference).write(to: temporaryDirectory.appendingPathComponent("ref-\(index + 1).png"))
            }

            let hits: [[ViewHit]]
            if let hierarchy = review.facts?.hierarchyXML {
                try hierarchy.write(to: temporaryDirectory.appendingPathComponent("hierarchy.xml"))
                hits = review.marks.map { HierarchyHitTester.views(for: $0.rect, hierarchyXML: hierarchy) }
            } else {
                hits = Array(repeating: [], count: review.marks.count)
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
