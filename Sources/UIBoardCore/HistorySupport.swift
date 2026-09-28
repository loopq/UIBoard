import Foundation

enum HistoryImplementation {
    static func scan(workspace: URL) -> [HistoryDay] {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let days = try? fileManager.contentsOfDirectory(
            at: workspace,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return days.compactMap { dayDirectory -> HistoryDay? in
            guard isDirectory(dayDirectory, fileManager: fileManager), validDate(dayDirectory.lastPathComponent) else {
                return nil
            }
            guard let entries = try? fileManager.contentsOfDirectory(
                at: dayDirectory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { return nil }

            let items = entries.compactMap { directory -> HistoryItem? in
                let name = directory.lastPathComponent
                guard
                    isDirectory(directory, fileManager: fileManager),
                    validTime(name),
                    fileManager.fileExists(atPath: directory.appendingPathComponent("review.md").path)
                else { return nil }
                return HistoryItem(time: name, dir: directory)
            }.sorted { timeSortKey($0.time) > timeSortKey($1.time) }
            return items.isEmpty ? nil : HistoryDay(date: dayDirectory.lastPathComponent, items: items)
        }.sorted { $0.date > $1.date }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func validDate(_ value: String) -> Bool {
        guard fixedDigits(value, groups: [4, 2, 2]) else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }

    private static func validTime(_ value: String) -> Bool {
        let fields = value.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3 || fields.count == 4 else { return false }
        let base = fields.prefix(3).joined(separator: "-")
        guard fixedDigits(base, groups: [2, 2, 2]) else { return false }
        if fields.count == 4 {
            guard let suffix = Int(fields[3]), suffix >= 2, String(suffix) == fields[3] else { return false }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH-mm-ss"
        formatter.isLenient = false
        return formatter.date(from: base) != nil
    }

    private static func fixedDigits(_ value: String, groups: [Int]) -> Bool {
        let fields = value.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == groups.count else { return false }
        return zip(fields, groups).allSatisfy { field, count in
            field.count == count && field.allSatisfy(\.isNumber)
        }
    }

    private static func timeSortKey(_ value: String) -> (String, Int) {
        let fields = value.split(separator: "-")
        let base = fields.prefix(3).joined(separator: "-")
        return (base, fields.count == 4 ? Int(fields[3]) ?? 1 : 1)
    }
}
