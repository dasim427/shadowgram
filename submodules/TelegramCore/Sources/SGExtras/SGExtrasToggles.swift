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
    case round60fps
    case roundHEVC
    case roundStartRear
    case roundMuted
    case roundKeepMusic
    case roundSaveToGallery
    case squareAvatars
    case hideStoryRings
    case snow
    case hideChatListSeparators
    case darkKeyboard
    case roundedFont
    case hideContactsTab
    case senderMiniAvatars
    case gifChatBackground
    case profileBadge
}

public extension SGExtrasManager {
    func isOn(_ toggle: SGToggle) -> Bool {
        return AYGSharedDefaults.store.bool(forKey: "SG.toggle." + toggle.rawValue)
    }

    func setOn(_ toggle: SGToggle, _ value: Bool) {
        AYGSharedDefaults.store.set(value, forKey: "SG.toggle." + toggle.rawValue)
        if toggle == .roundedFont {
            UserDefaults.standard.set(value, forKey: "SG.roundedFont")
        }
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
    let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: from) + #"(?![\p{L}\p{N}])"#
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

// Shadowgram: video message (round video) quality. Telegram records rounds at 400x400
// and 1 Mbit/s; these let the user go higher.
public extension SGExtrasManager {
    static let roundResolutionOptions: [Int32] = [400, 512, 640, 800]
    static let roundBitrateOptions: [Int] = [1000, 2000, 3000, 5000]

    var roundResolution: Int32 {
        get {
            let value = Int32(AYGSharedDefaults.store.integer(forKey: "SG.round.resolution"))
            return SGExtrasManager.roundResolutionOptions.contains(value) ? value : 400
        }
        set {
            AYGSharedDefaults.store.set(Int(newValue), forKey: "SG.round.resolution")
        }
    }

    var roundBitrateKbps: Int {
        get {
            let value = AYGSharedDefaults.store.integer(forKey: "SG.round.bitrate")
            return SGExtrasManager.roundBitrateOptions.contains(value) ? value : 1000
        }
        set {
            AYGSharedDefaults.store.set(newValue, forKey: "SG.round.bitrate")
        }
    }

    var roundFrameRate: Double {
        return self.isOn(.round60fps) ? 60.0 : 30.0
    }
}

// Shadowgram: appearance values that are not plain switches.
public extension SGExtrasManager {
    /// 0xRRGGBB presets for the message check marks; 0 keeps the theme color.
    static let checkColorOptions: [(String, Int)] = [
        ("Как в теме", 0),
        ("Зелёный", 0x34C759),
        ("Голубой", 0x5AC8FA),
        ("Фиолетовый", 0xAF52DE),
        ("Розовый", 0xFF2D55),
        ("Жёлтый", 0xFFCC00),
        ("Белый", 0xFFFFFF)
    ]

    var checkColorRGB: Int {
        get {
            return AYGSharedDefaults.store.integer(forKey: "SG.checkColor")
        }
        set {
            AYGSharedDefaults.store.set(newValue, forKey: "SG.checkColor")
        }
    }
}

public extension SGExtrasManager {
    static let bubbleWidthOptions: [Int] = [70, 80, 90, 100]
    static let chatListAvatarOptions: [Int] = [70, 80, 90, 100]

    /// Share of the normal maximum bubble width, in percent.
    var bubbleWidthPercent: Int {
        get {
            let value = AYGSharedDefaults.store.integer(forKey: "SG.bubbleWidth")
            return SGExtrasManager.bubbleWidthOptions.contains(value) ? value : 100
        }
        set {
            AYGSharedDefaults.store.set(newValue, forKey: "SG.bubbleWidth")
        }
    }

    /// Chat list avatar size, in percent of the normal one.
    var chatListAvatarPercent: Int {
        get {
            let value = AYGSharedDefaults.store.integer(forKey: "SG.chatListAvatar")
            return SGExtrasManager.chatListAvatarOptions.contains(value) ? value : 100
        }
        set {
            AYGSharedDefaults.store.set(newValue, forKey: "SG.chatListAvatar")
        }
    }
}

public extension SGExtrasManager {
    static let bubbleOpacityOptions: [Int] = [50, 70, 85, 100]

    /// Bubble background opacity, in percent.
    var bubbleOpacityPercent: Int {
        get {
            let value = AYGSharedDefaults.store.integer(forKey: "SG.bubbleOpacity")
            return SGExtrasManager.bubbleOpacityOptions.contains(value) ? value : 100
        }
        set {
            AYGSharedDefaults.store.set(newValue, forKey: "SG.bubbleOpacity")
        }
    }

    /// 0xRRGGBB for the bubble outline; 0 keeps the theme's.
    var bubbleOutlineRGB: Int {
        get {
            return AYGSharedDefaults.store.integer(forKey: "SG.bubbleOutline")
        }
        set {
            AYGSharedDefaults.store.set(newValue, forKey: "SG.bubbleOutline")
        }
    }
}

public extension SGExtrasManager {
    static let gifBackgroundOpacityOptions: [Int] = [30, 50, 70, 100]

    /// Opacity of the picked chat background over the wallpaper, in percent.
    var gifBackgroundOpacityPercent: Int {
        get {
            let value = AYGSharedDefaults.store.integer(forKey: "SG.gifBackgroundOpacity")
            return SGExtrasManager.gifBackgroundOpacityOptions.contains(value) ? value : 100
        }
        set {
            AYGSharedDefaults.store.set(newValue, forKey: "SG.gifBackgroundOpacity")
        }
    }
}

public extension SGExtrasManager {
    /// Extra text padding inside bubbles, in points: compact, standard, roomy.
    static let bubblePaddingOptions: [(String, Int)] = [("Компактно", -3), ("Стандарт", 0), ("Просторно", 4)]

    var bubblePadding: Int {
        get {
            let value = AYGSharedDefaults.store.integer(forKey: "SG.bubblePadding")
            return SGExtrasManager.bubblePaddingOptions.contains(where: { $0.1 == value }) ? value : 0
        }
        set {
            AYGSharedDefaults.store.set(newValue, forKey: "SG.bubblePadding")
        }
    }
}

public extension SGExtrasManager {
    /// Text shown after your own name in your profile, e.g. an emoji and a word.
    var profileBadgeText: String {
        get {
            return AYGSharedDefaults.store.string(forKey: "SG.profileBadge.text") ?? ""
        }
        set {
            AYGSharedDefaults.store.set(String(newValue.prefix(24)), forKey: "SG.profileBadge.text")
        }
    }

    /// The badge to draw, or nil when it is off or empty.
    var profileBadge: String? {
        let text = self.profileBadgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !self.isOn(.profileBadge) || text.isEmpty {
            return nil
        }
        return text
    }
}
