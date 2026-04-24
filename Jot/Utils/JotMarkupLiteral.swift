import Foundation

/// Lossless escape hatch for user-authored text that looks like Jot storage
/// markup but must remain plain visible text after serialize/deserialize cycles.
enum JotMarkupLiteral {
    static let tokenPrefix = "[[raw|"
    static let tokenSuffix = "]]"

    static func requiresEscaping(_ text: String) -> Bool {
        text.contains("[[")
            || text.contains("]]")
            || text.contains("[x]")
            || text.contains("[ ]")
    }

    static func escapeIfNeeded(_ text: String) -> String {
        requiresEscaping(text) ? encode(text) : text
    }

    static func encode(_ text: String) -> String {
        let data = Data(text.utf8)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(tokenPrefix)\(encoded)\(tokenSuffix)"
    }

    static func decodePayload(_ payload: String) -> String? {
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: padding))
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeToken(_ token: String) -> String? {
        guard token.hasPrefix(tokenPrefix), token.hasSuffix(tokenSuffix) else { return nil }
        let start = token.index(token.startIndex, offsetBy: tokenPrefix.count)
        let end = token.index(token.endIndex, offsetBy: -tokenSuffix.count)
        guard start <= end else { return nil }
        return decodePayload(String(token[start..<end]))
    }

    static func consumeToken(in text: String, at index: String.Index) -> (decoded: String, end: String.Index)? {
        guard text[index...].hasPrefix(tokenPrefix),
              let close = text[index...].range(of: tokenSuffix) else { return nil }
        let payloadStart = text.index(index, offsetBy: tokenPrefix.count)
        let payload = String(text[payloadStart..<close.lowerBound])
        guard let decoded = decodePayload(payload) else { return nil }
        return (decoded, close.upperBound)
    }

    static func replacingRawTokens(in text: String) -> String {
        guard text.contains(tokenPrefix) else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            if let token = consumeToken(in: text, at: index) {
                result.append(token.decoded)
                index = token.end
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }

    static func protectingRawTokens(
        in text: String,
        transform: (String) -> String
    ) -> String {
        guard text.contains(tokenPrefix) else { return transform(text) }

        var protected = ""
        protected.reserveCapacity(text.count)
        var replacements: [String: String] = [:]
        var index = text.startIndex
        var counter = 0

        while index < text.endIndex {
            if let token = consumeToken(in: text, at: index) {
                let placeholder = "\u{F8FF}JOTRAW\(counter)\u{F8FF}"
                counter += 1
                replacements[placeholder] = token.decoded
                protected += placeholder
                index = token.end
            } else {
                protected.append(text[index])
                index = text.index(after: index)
            }
        }

        var transformed = transform(protected)
        for (placeholder, decoded) in replacements {
            transformed = transformed.replacingOccurrences(of: placeholder, with: decoded)
        }
        return transformed
    }
}
