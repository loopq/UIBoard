import CoreGraphics
import Foundation
import UIBoardCore

// 用法：uiboard-export <spec.json>
// 按 JSON 描述组装 Review，经 ReviewExporter.export 导出（与 App 同一条路径），stdout 输出 review 目录绝对路径。

struct Spec: Decodable {
    struct FrameSpec: Decodable {
        var image: String
        var serial: String?
        var model: String?
        var density: Int?
        var activity: String?
        var hierarchy: String?
    }
    struct MarkSpec: Decodable {
        var frame: Int?
        var rect: [Double]
        var note: String?
    }
    var workspace: String
    var figma: String?
    var refs: [String]?
    var frames: [FrameSpec]
    var marks: [MarkSpec]
}

struct Failure: Error, CustomStringConvertible {
    let description: String
}

func readFile(_ path: String) throws -> Data {
    guard let data = FileManager.default.contents(atPath: path) else { throw Failure(description: "文件不存在或不可读：\(path)") }
    return data
}

func run() throws -> URL {
    let args = CommandLine.arguments
    guard args.count == 2 else { throw Failure(description: "用法：uiboard-export <spec.json>") }
    let spec = try JSONDecoder().decode(Spec.self, from: try readFile(args[1]))
    guard !spec.frames.isEmpty else { throw Failure(description: "frames 不能为空") }
    guard !spec.marks.isEmpty else { throw Failure(description: "marks 不能为空") }

    let frames: [Frame] = try spec.frames.map { f in
        let image = try ImageIngest.decode(try readFile(f.image))
        let hierarchy = try f.hierarchy.map(readFile)
        let hasFacts = f.serial != nil || f.density != nil || f.activity != nil || hierarchy != nil
        let facts = hasFacts ? DeviceFacts(serial: f.serial ?? "", model: f.model, densityDpi: f.density,
                                           activity: f.activity, hierarchyXML: hierarchy) : nil
        return Frame(image: image, facts: facts)
    }
    let marks: [Mark] = try spec.marks.enumerated().map { index, m in
        let frame = m.frame ?? 0
        guard frames.indices.contains(frame) else { throw Failure(description: "mark #\(index + 1) 的 frame \(frame) 越界") }
        guard m.rect.count == 4 else { throw Failure(description: "mark #\(index + 1) 的 rect 需要 4 个数 [x,y,w,h]") }
        let rect = CGRect(x: m.rect[0], y: m.rect[1], width: m.rect[2], height: m.rect[3])
        let bounds = CGRect(origin: .zero, size: frames[frame].size)
        guard rect.width >= 0, rect.height >= 0, bounds.contains(rect.origin),
              rect.maxX <= bounds.maxX, rect.maxY <= bounds.maxY else {
            throw Failure(description: "mark #\(index + 1) 的 rect \(m.rect) 超出图片 \(Int(bounds.width))x\(Int(bounds.height))")
        }
        return Mark(rect: rect, note: m.note ?? "", frame: frame)
    }
    let refs = try (spec.refs ?? []).map { try ImageIngest.decode(try readFile($0)) }
    let review = Review(frames: frames, marks: marks, refs: refs, figmaURL: spec.figma ?? "")
    return try ReviewExporter.export(review, workspace: URL(fileURLWithPath: spec.workspace, isDirectory: true), now: Date())
}

do {
    print(try run().path)
} catch {
    FileHandle.standardError.write(Data("uiboard-export: \(error)\n".utf8))
    exit(1)
}
