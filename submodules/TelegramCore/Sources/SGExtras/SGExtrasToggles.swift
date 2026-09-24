import Foundation

// Shadowgram: simple on/off switches for client-side tweaks. Each one is read at the
// point in the Telegram code it affects, so there is no state to keep in sync.
public enum SGToggle: String, CaseIterable {
    case hideEditedMark
    case hideChannelViews
    case hideGreetingSticker
    case exactLastSeen
    case noCallRating
    case antiCaps
    case textReplacement
}

public extension SGExtrasManager {
    func isOn(_ toggle: SGToggle) -> Bool {
        return AYGSharedDefaults.store.bool(forKey: "SG.toggle." + toggle.rawValue)
    }

    func setOn(_ toggle: SGToggle, _ value: Bool) {
        AYGSharedDefaults.store.set(value, forKey: "SG.toggle." + toggle.rawValue)
        NotificationCenter.default.post(name: SGExtrasManager.settingsChangedNotification, object: nil)
    }

    /// One rule per line: `from = to`. Kept as the raw text the user typed so the editor
    /// shows it back unchanged.
    var textReplacementRulesText: String {
        get {
            return AYGSharedDefaults.store.string(forKey: "SG.textReplacement.rules") ?? ""
        }
        set {
            AYGSharedDefaults.store.set(newValue, forKey: "SG.textReplacement.rules")
        }
    }

    var textReplacementRules: [(String, String)] {
        var result: [(String, String)] = []
        for line in self.textReplacementRulesText.components(separatedBy: .newlines) {
            guard let range = line.range(of: "=") else {
                continue
            }
            let from = line[line.startIndex ..< range.lowerBound].trimmingCharacters(in: .whitespaces)
            let to = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !from.isEmpty {
                result.append((from, to))
            }
        }
        return result
    }

    /// Rewrites the text of an outgoing message. `hasEntities` means the text carries
    /// formatting whose offsets would break if the length changed, so only
    /// length-preserving rewrites are applied then.
    func transformOutgoingText(_ text: String, hasEntities: Bool) -> String {
        var text = text
        if self.isOn(.textReplacement) && !hasEntities {
            for (from, to) in self.textReplacementRules {
                text = sgReplaceWholeWords(in: text, from: from, to: to)
            }
        }
        if self.isOn(.antiCaps) {
            let fixed = sgDecapitalize(text)
            if !hasEntities || fixed.utf16.count == text.utf16.count {
                text = fixed
            }
        }
        return text
    }
}

private func sgReplaceWholeWords(in text: String, from: String, to: String) -> String {
    let pattern = "(?<![\p{L}\p{N}])" + NSRegularExpression.escapedPattern(for: from) + "(?![\p{L}\p{N}])"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return text
    }
    return regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: NSRegularExpression.escapedTemplate(for: to))
}

/// "ПРИВЕТ ВСЕМ. КАК ДЕЛА" -> "Привет всем. Как дела". Only fires when the message is
/// shouting: at least four letters and none of them lowercase.
private func sgDecapitalize(_ text: String) -> String {
    let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
    guard letters.count >= 4, !letters.contains(where: { CharacterSet.lowercaseLetters.contains($0) }) else {
        return text
    }
    var result = ""
    var capitalizeNext = true
    for character in text {
        if character.isLetter {
            result += capitalizeNext ? String(character) : character.lowercased()
            capitalizeNext = false
        } else {
            result.append(character)
            if character == "." || character == "!" || character == "?" || character == "\n" {
                capitalizeNext = true
            }
        }
    }
    return result
}
