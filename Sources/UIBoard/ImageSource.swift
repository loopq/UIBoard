import AppKit
import UniformTypeIdentifiers

enum ImageSource {
    static let dropTypes: [UTType] = [.fileURL, .image]

    static func pasteboardImage() -> Data? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            return data
        }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first.flatMap(imageFile)
    }

    static var pasteboardHasText: Bool {
        NSPasteboard.general.string(forType: .string) != nil
    }

    static func load(_ providers: [NSItemProvider]) async -> [Data] {
        var result: [Data] = []
        for provider in providers {
            if let url = await fileURL(provider) {
                if let data = imageFile(url) { result.append(data) }
            } else if let data = await imageData(provider) {
                result.append(data)
            }
        }
        return result
    }

    static func open(multiple: Bool) -> [Data] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = multiple
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap(imageFile)
    }

    private static func imageFile(_ url: URL) -> Data? {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func fileURL(_ provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    private static func imageData(_ provider: NSItemProvider) async -> Data? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
