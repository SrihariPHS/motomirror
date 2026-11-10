import Foundation

public struct UIBounds: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var centerX: Int { x + width / 2 }
    public var centerY: Int { y + height / 2 }
}

public struct UIElement: Codable, Equatable, Sendable {
    public let text: String?
    public let resourceID: String?
    public let contentDescription: String?
    public let className: String?
    public let bounds: UIBounds
    public let clickable: Bool
    public let enabled: Bool

    public init(
        text: String? = nil,
        resourceID: String? = nil,
        contentDescription: String? = nil,
        className: String? = nil,
        bounds: UIBounds,
        clickable: Bool = false,
        enabled: Bool = true
    ) {
        self.text = text
        self.resourceID = resourceID
        self.contentDescription = contentDescription
        self.className = className
        self.bounds = bounds
        self.clickable = clickable
        self.enabled = enabled
    }

    public var label: String {
        text?.nonEmpty ?? contentDescription?.nonEmpty ?? resourceID?.nonEmpty ?? className?.nonEmpty ?? ""
    }
}

public struct UIHierarchy: Codable, Sendable {
    public let elements: [UIElement]
    public init(elements: [UIElement]) { self.elements = elements }
}

public enum UIHierarchyParser {
    public static func parse(_ xml: String) throws -> UIHierarchy {
        guard let data = xml.data(using: .utf8) else {
            throw MotoMirrorError.parseFailure("UI hierarchy was not valid UTF-8.")
        }
        let delegate = HierarchyDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw MotoMirrorError.parseFailure(
                "UI hierarchy XML was malformed: \(parser.parserError?.localizedDescription ?? "unknown error")"
            )
        }
        return UIHierarchy(elements: delegate.elements)
    }

    public static func bounds(from raw: String?) -> UIBounds? {
        guard let raw else { return nil }
        let numbers = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count >= 4 else { return nil }
        let x1 = numbers[0], y1 = numbers[1], x2 = numbers[2], y2 = numbers[3]
        guard x2 >= x1, y2 >= y1 else { return nil }
        return UIBounds(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }
}

private final class HierarchyDelegate: NSObject, XMLParserDelegate {
    var elements: [UIElement] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "node" else { return }
        guard let bounds = UIHierarchyParser.bounds(from: attributeDict["bounds"]) else { return }
        elements.append(
            UIElement(
                text: attributeDict["text"],
                resourceID: attributeDict["resource-id"],
                contentDescription: attributeDict["content-desc"],
                className: attributeDict["class"],
                bounds: bounds,
                clickable: attributeDict["clickable"] == "true",
                enabled: attributeDict["enabled"] != "false"
            )
        )
    }
}

public enum DeviceOutputParser {
    public static func packages(_ output: String) -> [InstalledApp] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("package:") else { return nil }
            let value = String(trimmed.dropFirst("package:".count))
            guard !value.isEmpty else { return nil }
            return InstalledApp(package: value)
        }
    }

    public static func foreground(_ output: String) -> ForegroundApp? {
        let pattern = #"(?:topResumedActivity|mResumedActivity)\s*[=:]\s*ActivityRecord\{[^ ]+ [^ ]+ ([^/\s]+)/([^ }\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges >= 3,
              let packageRange = Range(match.range(at: 1), in: output),
              let activityRange = Range(match.range(at: 2), in: output)
        else { return nil }
        return ForegroundApp(
            package: String(output[packageRange]),
            activity: String(output[activityRange])
        )
    }

    public static func volume(_ output: String) -> VolumeInfo? {
        let pattern = #"volume is (\d+) in range \[0\.\.(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges >= 3,
              let levelRange = Range(match.range(at: 1), in: output),
              let maxRange = Range(match.range(at: 2), in: output),
              let level = Int(output[levelRange]),
              let maximum = Int(output[maxRange])
        else { return nil }
        return VolumeInfo(level: level, max: maximum)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
