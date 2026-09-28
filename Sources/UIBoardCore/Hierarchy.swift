import CoreGraphics
import Foundation

enum HierarchyHitTester {
    static func views(for rect: CGRect, hierarchyXML: Data) -> [ViewHit] {
        let parser = XMLParser(data: hierarchyXML)
        let delegate = HierarchyParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else { return [] }

        let query = rect.size == .zero
            ? CGRect(x: rect.origin.x - 1, y: rect.origin.y - 1, width: 2, height: 2)
            : rect
        // Window-sized containers say nothing about location (the activity already names the screen).
        // Ceiling: an id'd full-screen custom view is dropped too; the skill then falls back to the activity.
        let windowArea = delegate.nodes.map { $0.hit.bounds.width * $0.hit.bounds.height }.max() ?? 0

        return delegate.nodes.compactMap { node -> ScoredHit? in
            guard
                !node.hit.resourceId.isEmpty,
                !node.hit.resourceId.hasPrefix("android:id/"),
                node.hit.bounds.width > 0,
                node.hit.bounds.height > 0,
                node.hit.bounds.width * node.hit.bounds.height < windowArea * 0.9
            else { return nil }

            let intersection = query.intersection(node.hit.bounds)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }
            let intersectionArea = intersection.width * intersection.height
            let queryArea = query.width * query.height
            let boundsArea = node.hit.bounds.width * node.hit.bounds.height
            let unionArea = queryArea + boundsArea - intersectionArea
            guard unionArea > 0 else { return nil }
            return ScoredHit(hit: node.hit, score: intersectionArea / unionArea, area: boundsArea, order: node.order)
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.area != $1.area { return $0.area < $1.area }
            return $0.order < $1.order
        }
        .prefix(3)
        .map(\.hit)
    }
}

private struct ParsedNode {
    let hit: ViewHit
    let order: Int
}

private struct ScoredHit {
    let hit: ViewHit
    let score: CGFloat
    let area: CGFloat
    let order: Int
}

private final class HierarchyParserDelegate: NSObject, XMLParserDelegate {
    private(set) var nodes: [ParsedNode] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard
            elementName == "node",
            let boundsString = attributeDict["bounds"],
            let bounds = Self.parseBounds(boundsString)
        else { return }
        nodes.append(ParsedNode(
            hit: ViewHit(
                resourceId: attributeDict["resource-id"] ?? "",
                className: attributeDict["class"] ?? "",
                bounds: bounds
            ),
            order: nodes.count
        ))
    }

    private static func parseBounds(_ value: String) -> CGRect? {
        let values = value.components(separatedBy: CharacterSet(charactersIn: "[] ,"))
            .filter { !$0.isEmpty }
            .compactMap(Double.init)
        guard values.count == 4 else { return nil }
        let (x1, y1, x2, y2) = (values[0], values[1], values[2], values[3])
        return CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }
}
