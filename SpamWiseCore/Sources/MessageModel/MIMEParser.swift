import Foundation
import CoreFoundation

/// Deliberately bounded subset of RFC 5322/MIME. Unsupported or ambiguous mail is unclassified.
public struct MIMEParser: Sendable {
    public init() {}
    public func parse(_ data: Data) throws -> ParsedMessage {
        guard data.count <= 2_000_000 else { throw ParseError.tooLarge }
        // A byte-preserving intermediate avoids corrupting non-UTF8 MIME parts.
        let source = String(data.map { Character(UnicodeScalar($0)) }).replacingOccurrences(of: "\r\n", with: "\n")
        let (headers, _) = try split(source)
        guard let from = headers["from"]?.first, headers["from"]?.count == 1,
              let address = Self.address(from) else { throw ParseError.malformed }
        var count = 0
        let content = try part(source, depth: 0, count: &count)
        let display = from.components(separatedBy: "<").first ?? ""
        let name = from.contains("<") ? try Self.decodeWords(display.trimmingCharacters(in: CharacterSet(charactersIn: " \""))) : ""
        return ParsedMessage(headers: headers, fromAddress: address, fromDisplayName: name,
                             subject: try Self.decodeWords(headers["subject"]?.first ?? "(No subject)"),
                             text: String(content.text.prefix(100_000)),
                             urls: Array(Set(content.urls)).sorted().prefix(40).map { $0 }, hash: stableHash(data))
    }

    public static func address(_ value: String) -> String? {
        let hits = matches(#"[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9.-]*[A-Z0-9])?"#, value, options: .caseInsensitive)
        guard hits.count == 1 else { return nil }
        return hits[0][0].lowercased()
    }

    private func split(_ source: String) throws -> ([String: [String]], String) {
        guard let separator = source.range(of: "\n\n"), source[..<separator.lowerBound].utf8.count < 65_536 else { throw ParseError.malformed }
        var lines: [String] = []
        for line in source[..<separator.lowerBound].components(separatedBy: "\n") {
            if line.first == " " || line.first == "\t" {
                guard !lines.isEmpty else { throw ParseError.malformed }
                lines[lines.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else { lines.append(line) }
        }
        var headers: [String: [String]] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.malformed }
            let key = String(line[..<colon]).lowercased()
            guard !key.isEmpty, key.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { throw ParseError.malformed }
            headers[key, default: []].append(String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
        for key in ["content-type", "content-transfer-encoding"] where (headers[key]?.count ?? 0) > 1 { throw ParseError.malformed }
        return (headers, String(source[separator.upperBound...]))
    }

    private struct Content { var text: String; var urls: [String]; var plain: Bool }
    private func part(_ source: String, depth: Int, count: inout Int) throws -> Content {
        count += 1
        guard depth <= 12, count <= 128 else { throw ParseError.tooLarge }
        let (headers, raw) = try split(source)
        let contentType = headers["content-type"]?.first ?? "text/plain"
        let mime = contentType.components(separatedBy: ";")[0].lowercased().trimmingCharacters(in: .whitespaces)
        if headers["content-disposition"]?.first?.lowercased().hasPrefix("attachment") == true {
            return Content(text: "", urls: [], plain: false)
        }
        if mime.hasPrefix("multipart/") {
            guard let boundary = Self.parameter("boundary", in: contentType), !boundary.isEmpty, boundary.count <= 200 else { throw ParseError.malformed }
            var parts: [String] = [], current: [String]? = nil, closed = false
            for line in raw.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "--" + boundary || trimmed == "--" + boundary + "--" {
                    if let current { parts.append(current.joined(separator: "\n")) }
                    current = []
                    if trimmed.hasSuffix("--") { closed = true; break }
                } else if current != nil { current?.append(line) }
            }
            guard closed, !parts.isEmpty else { throw ParseError.malformed }
            var contents: [Content] = []
            for p in parts { contents.append(try part(p, depth: depth + 1, count: &count)) }
            let chosen = mime == "multipart/alternative" ? [contents.first(where: { $0.plain && !$0.text.isEmpty }) ?? contents.last!] : contents
            return Content(text: chosen.map(\.text).joined(separator: "\n"), urls: contents.flatMap(\.urls), plain: chosen.contains(where: \.plain))
        }
        guard ["text/plain", "text/html"].contains(mime) else { return Content(text: "", urls: [], plain: false) }
        let encoding = headers["content-transfer-encoding"]?.first?.lowercased() ?? "8bit"
        let bytes: Data
        switch encoding {
        case "base64":
            let compact = raw.filter { !$0.isWhitespace }
            guard let decoded = Data(base64Encoded: compact) else { throw ParseError.invalidEncoding }
            bytes = decoded
        case "quoted-printable": bytes = try Self.quotedPrintable(raw)
        case "7bit", "8bit", "binary": bytes = Data(raw.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
        default: throw ParseError.invalidEncoding
        }
        let decoded = try Self.decode(bytes, charset: Self.parameter("charset", in: contentType) ?? "utf-8")
        var urls = Self.matches(#"https?://[^\s<>"']+"#, decoded, options: .caseInsensitive).map { $0[0].trimmingCharacters(in: CharacterSet(charactersIn: ".,);")) }
        let text = mime == "text/html" ? Self.htmlText(decoded) : decoded
        urls = urls.filter { URL(string: $0)?.host != nil }
        return Content(text: text.trimmingCharacters(in: .whitespacesAndNewlines), urls: urls, plain: mime == "text/plain")
    }

    private static func parameter(_ key: String, in value: String) -> String? {
        let hits = matches("(?:^|;)\\s*" + key + #"\s*=\s*(?:"([^"]*)"|([^;\s]+))"#, value, options: .caseInsensitive)
        guard let first = hits.first else { return nil }
        return first[1].isEmpty ? first[2] : first[1]
    }
    private static func decode(_ data: Data, charset: String) throws -> String {
        let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cf != kCFStringEncodingInvalidId else { throw ParseError.unsupportedCharset }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        guard let text = String(data: data, encoding: encoding) else { throw ParseError.invalidEncoding }
        return text
    }
    private static func quotedPrintable(_ source: String) throws -> Data {
        let bytes = Array(source.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) })
        var result = Data(), i = 0
        while i < bytes.count {
            if bytes[i] == 61 {
                if i + 1 < bytes.count && bytes[i + 1] == 10 { i += 2; continue }
                guard i + 2 < bytes.count, let byte = UInt8(String(bytes: bytes[(i+1)...(i+2)], encoding: .ascii) ?? "", radix: 16) else { throw ParseError.invalidEncoding }
                result.append(byte); i += 3
            } else { result.append(bytes[i]); i += 1 }
        }
        return result
    }
    private static func decodeWords(_ value: String) throws -> String {
        let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#
        let regex = try NSRegularExpression(pattern: pattern)
        var result = value
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            func field(_ n: Int) -> String { String(value[Range(match.range(at: n), in: value)!]) }
            let bytes: Data
            if field(2).lowercased() == "b" {
                guard let decoded = Data(base64Encoded: field(3)) else { throw ParseError.invalidEncoding }
                bytes = decoded
            } else { bytes = try quotedPrintable(field(3).replacingOccurrences(of: "_", with: " ")) }
            result.replaceSubrange(Range(match.range, in: result)!, with: try decode(bytes, charset: field(1)))
        }
        // Unencoded UTF-8 headers were byte-preserved above.
        if !value.contains("=?"), let decoded = String(data: Data(value.unicodeScalars.map { UInt8(truncatingIfNeeded: $0.value) }), encoding: .utf8) { return decoded }
        return result
    }
    private static func htmlText(_ html: String) -> String {
        var text = html
        for pattern in [#"(?is)<(script|style|head)\b[^>]*>.*?</\1\s*>"#, #"(?s)<!--.*?-->"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"(?is)<(?:br|/p|/div|/li)\b[^>]*>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        for (entity, character) in [("&lt;","<"),("&gt;",">"),("&quot;","\""),("&#39;","'"),("&nbsp;"," "),("&amp;","&")] { text = text.replacingOccurrences(of: entity, with: character) }
        let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
        for match in (regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []).reversed() {
            let number = String(text[Range(match.range(at: 1), in: text)!])
            let value = number.hasPrefix("x") ? UInt32(number.dropFirst(), radix: 16) : UInt32(number)
            if let value, let scalar = UnicodeScalar(value), let range = Range(match.range, in: text) { text.replaceSubrange(range, with: String(scalar)) }
        }
        return text.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
    }
    private static func matches(_ pattern: String, _ text: String, options: NSRegularExpression.Options = []) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }
}
