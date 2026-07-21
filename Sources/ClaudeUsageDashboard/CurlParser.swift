import Foundation

enum CurlParser {
    struct ParsedConfig {
        let usageURL: String
        let cookie: String
    }

    static func parse(_ curlText: String) -> ParsedConfig? {
        guard let usageURL = firstMatch(
            in: curlText,
            pattern: #"curl\s+(?:-\S+\s+)*['"]?(https://claude\.ai/api/organizations/[^\s'"]+)"#
        ) else { return nil }

        var cookie = firstMatch(
            in: curlText,
            pattern: #"-H\s+['"]cookie:\s*([^'"]+)['"]"#,
            options: [.caseInsensitive]
        )
        if cookie == nil {
            cookie = firstMatch(
                in: curlText,
                pattern: #"-b\s+['"]([^'"]+)['"]"#,
                options: [.caseInsensitive]
            )
        }
        guard let cookie else { return nil }

        return ParsedConfig(
            usageURL: usageURL,
            cookie: cookie.trimmingCharacters(in: .whitespaces)
        )
    }

    private static func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[groupRange])
    }
}
