import Foundation

struct ClipboardAutoDownloadCandidate {
    let text: String
    let fingerprint: String

    static func resolve(from text: String, lastHandledFingerprint: String?) -> ClipboardAutoDownloadCandidate? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, let urlString = firstURLString(in: trimmedText) else {
            return nil
        }

        guard urlString != lastHandledFingerprint else {
            return nil
        }

        return ClipboardAutoDownloadCandidate(text: trimmedText, fingerprint: urlString)
    }

    private static func firstURLString(in text: String) -> String? {
        let pattern = #"https?://[^\s]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }

        let rawURLString = String(text[range])
        let trimmedURLString = rawURLString.trimmingCharacters(in: CharacterSet(charactersIn: ".,，。!！?？)）]】}\"'"))
        guard URL(string: trimmedURLString) != nil else {
            return nil
        }

        return trimmedURLString
    }
}
