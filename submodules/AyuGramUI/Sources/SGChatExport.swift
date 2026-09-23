import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import UndoUI

// Shadowgram: exports one chat the way Telegram Desktop's "Export chat history" does —
// result.json in the same schema plus a readable messages.html — and hands both files
// to the system share sheet. Media files are not downloaded; they are listed with the
// same placeholder Telegram Desktop writes when media export is switched off.

private let sgExportMaxMessages = 50000
private let sgFileNotIncluded = "(File not included. Change data exporting settings to download.)"

private func sgPeerName(_ peer: Peer?) -> String {
    guard let peer = peer else {
        return ""
    }
    if let user = peer as? TelegramUser {
        let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Deleted Account" : name
    } else if let channel = peer as? TelegramChannel {
        return channel.title
    } else if let group = peer as? TelegramGroup {
        return group.title
    }
    return ""
}

private func sgPeerExportId(_ peer: Peer) -> String {
    let value = peer.id.id._internalGetInt64Value()
    if peer is TelegramUser {
        return "user\(value)"
    } else if peer is TelegramChannel {
        return "channel\(value)"
    } else {
        return "chat\(value)"
    }
}

private func sgChatType(_ peer: Peer, accountPeerId: PeerId) -> String {
    if peer.id == accountPeerId {
        return "saved_messages"
    }
    if let user = peer as? TelegramUser {
        return user.botInfo != nil ? "bot_chat" : "personal_chat"
    }
    if let channel = peer as? TelegramChannel {
        let isPublic = !(channel.addressName ?? "").isEmpty
        if case .broadcast = channel.info {
            return isPublic ? "public_channel" : "private_channel"
        }
        return isPublic ? "public_supergroup" : "private_supergroup"
    }
    return "private_group"
}

private let sgExportDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter
}()

private let sgHtmlDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
    return formatter
}()

private func sgEntityTypeName(_ type: MessageTextEntityType) -> (String, [String: Any])? {
    switch type {
    case .Mention:
        return ("mention", [:])
    case .Hashtag:
        return ("hashtag", [:])
    case .BotCommand:
        return ("bot_command", [:])
    case .Url:
        return ("link", [:])
    case .Email:
        return ("email", [:])
    case .Bold:
        return ("bold", [:])
    case .Italic:
        return ("italic", [:])
    case .Code:
        return ("code", [:])
    case let .Pre(language):
        return ("pre", ["language": language ?? ""])
    case let .TextUrl(url):
        return ("text_link", ["href": url])
    case let .TextMention(peerId):
        return ("mention_name", ["user_id": peerId.id._internalGetInt64Value()])
    case .PhoneNumber:
        return ("phone", [:])
    case .Strikethrough:
        return ("strikethrough", [:])
    case .BlockQuote:
        return ("blockquote", [:])
    case .Underline:
        return ("underline", [:])
    case .BankCard:
        return ("bank_card", [:])
    case .Spoiler:
        return ("spoiler", [:])
    case let .CustomEmoji(_, fileId):
        return ("custom_emoji", ["document_id": fileId])
    default:
        return nil
    }
}

/// Splits the text into Telegram Desktop's `text_entities` parts. Entity ranges are
/// UTF-16 offsets; overlapping (nested) entities keep only the outermost one.
private func sgTextEntities(text: String, entities: [MessageTextEntity]) -> [[String: Any]] {
    let nsText = text as NSString
    let length = nsText.length
    var parts: [[String: Any]] = []
    var position = 0
    for entity in entities.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
        let lower = max(0, min(entity.range.lowerBound, length))
        let upper = max(lower, min(entity.range.upperBound, length))
        if lower < position || lower == upper {
            continue
        }
        guard let (typeName, extra) = sgEntityTypeName(entity.type) else {
            continue
        }
        if lower > position {
            parts.append(["type": "plain", "text": nsText.substring(with: NSRange(location: position, length: lower - position))])
        }
        var part: [String: Any] = ["type": typeName, "text": nsText.substring(with: NSRange(location: lower, length: upper - lower))]
        for (key, value) in extra {
            part[key] = value
        }
        parts.append(part)
        position = upper
    }
    if position < length {
        parts.append(["type": "plain", "text": nsText.substring(from: position)])
    }
    return parts
}

private func sgHtmlEscape(_ text: String) -> String {
    return text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "\n", with: "<br>")
}

private struct SGExportedMessage {
    let json: [String: Any]
    let html: String
}

private func sgExportMessage(_ message: Message) -> SGExportedMessage {
    var json: [String: Any] = [:]
    json["id"] = Int(message.id.id)

    var isService = false
    var mediaDescription: String?
    for media in message.media {
        if media is TelegramMediaAction {
            isService = true
        } else if let image = media as? TelegramMediaImage {
            json["photo"] = sgFileNotIncluded
            if let largest = image.representations.last {
                json["width"] = Int(largest.dimensions.width)
                json["height"] = Int(largest.dimensions.height)
            }
            mediaDescription = "Фото"
        } else if let file = media as? TelegramMediaFile {
            json["file"] = sgFileNotIncluded
            json["mime_type"] = file.mimeType
            if file.isInstantVideo {
                json["media_type"] = "video_message"
                mediaDescription = "Видеосообщение"
            } else if file.isVoice {
                json["media_type"] = "voice_message"
                mediaDescription = "Голосовое сообщение"
            } else if file.isSticker {
                json["media_type"] = "sticker"
                mediaDescription = "Стикер"
            } else if file.isAnimated {
                json["media_type"] = "animation"
                mediaDescription = "GIF"
            } else if file.isVideo {
                json["media_type"] = "video_file"
                mediaDescription = "Видео"
            } else if file.isMusic {
                json["media_type"] = "audio_file"
                mediaDescription = "Аудио"
            } else {
                mediaDescription = "Файл"
            }
        } else if media is TelegramMediaPoll {
            mediaDescription = "Опрос"
        } else if media is TelegramMediaMap {
            mediaDescription = "Геопозиция"
        } else if media is TelegramMediaContact {
            mediaDescription = "Контакт"
        }
    }

    json["type"] = isService ? "service" : "message"
    json["date"] = sgExportDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
    json["date_unixtime"] = "\(message.timestamp)"

    let authorName = sgPeerName(message.author)
    if let author = message.author {
        json[isService ? "actor" : "from"] = authorName
        json[isService ? "actor_id" : "from_id"] = sgPeerExportId(author)
    }

    var entities: [MessageTextEntity] = []
    for attribute in message.attributes {
        if let attribute = attribute as? ReplyMessageAttribute {
            json["reply_to_message_id"] = Int(attribute.messageId.id)
        } else if let attribute = attribute as? EditedMessageAttribute {
            json["edited"] = sgExportDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(attribute.date)))
            json["edited_unixtime"] = "\(attribute.date)"
        } else if let attribute = attribute as? TextEntitiesMessageAttribute {
            entities = attribute.entities
        }
    }
    if let forwardInfo = message.forwardInfo {
        json["forwarded_from"] = forwardInfo.author.flatMap { sgPeerName($0) } ?? forwardInfo.authorSignature ?? ""
    }

    let parts = sgTextEntities(text: message.text, entities: entities)
    if parts.count == 1, let only = parts.first, (only["type"] as? String) == "plain" {
        json["text"] = message.text
    } else if parts.isEmpty {
        json["text"] = ""
    } else {
        json["text"] = parts.map { part -> Any in
            if (part["type"] as? String) == "plain" {
                return part["text"] ?? ""
            }
            return part
        }
    }
    json["text_entities"] = parts

    var html = "<div class=\"message\" id=\"message\(message.id.id)\">"
    html += "<div class=\"meta\"><span class=\"from\">\(sgHtmlEscape(authorName))</span> "
    html += "<span class=\"date\">\(sgHtmlDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp))))</span></div>"
    if let forwarded = json["forwarded_from"] as? String, !forwarded.isEmpty {
        html += "<div class=\"forwarded\">Переслано от \(sgHtmlEscape(forwarded))</div>"
    }
    if let replyTo = json["reply_to_message_id"] as? Int {
        html += "<div class=\"reply\"><a href=\"#message\(replyTo)\">В ответ на сообщение</a></div>"
    }
    if let mediaDescription = mediaDescription {
        html += "<div class=\"media\">[\(mediaDescription)]</div>"
    }
    if !message.text.isEmpty {
        html += "<div class=\"text\">\(sgHtmlEscape(message.text))</div>"
    } else if isService {
        html += "<div class=\"text service\">Служебное сообщение</div>"
    }
    html += "</div>\n"

    return SGExportedMessage(json: json, html: html)
}

private func sgLoadAllMessages(engine: TelegramEngine, peerId: PeerId, state: SearchMessagesState?, collected: [Message], progress: @escaping (Int) -> Void) -> Signal<[Message], NoError> {
    return engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: state, limit: 100)
    |> take(1)
    |> mapToSignal { result, updatedState -> Signal<[Message], NoError> in
        var seen = Set(collected.map { $0.id })
        var all = collected
        for message in result.messages where !seen.contains(message.id) {
            seen.insert(message.id)
            all.append(message)
        }
        progress(all.count)
        let addedNothing = all.count == collected.count
        if result.completed || addedNothing || all.count >= sgExportMaxMessages {
            return .single(all)
        }
        return sgLoadAllMessages(engine: engine, peerId: peerId, state: updatedState, collected: all, progress: progress)
    }
}

private func sgWriteExport(chatPeer: Peer, accountPeerId: PeerId, messages: [Message]) -> [URL]? {
    let sorted = messages.sorted(by: { $0.id.id < $1.id.id })
    let exported = sorted.map(sgExportMessage)

    let chatName = sgPeerName(chatPeer)
    let root: [String: Any] = [
        "name": chatName,
        "type": sgChatType(chatPeer, accountPeerId: accountPeerId),
        "id": chatPeer.id.id._internalGetInt64Value(),
        "messages": exported.map { $0.json }
    ]

    let folderName = "ChatExport_\(sgExportDateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-"))"
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(folderName, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jsonData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let jsonURL = folder.appendingPathComponent("result.json")
        try jsonData.write(to: jsonURL)

        var html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(sgHtmlEscape(chatName))</title><style>"
        html += "body{font-family:-apple-system,Helvetica,Arial,sans-serif;background:#e7ebf0;margin:0;padding:16px}"
        html += "h1{font-size:20px}.message{background:#fff;border-radius:10px;padding:8px 12px;margin:6px 0;max-width:720px}"
        html += ".meta{font-size:13px;color:#70777b;margin-bottom:4px}.from{color:#3892db;font-weight:600}"
        html += ".media,.forwarded,.reply{font-size:13px;color:#70777b}.text{font-size:15px;white-space:normal;word-wrap:break-word}.service{color:#70777b;font-style:italic}"
        html += "</style></head><body><h1>\(sgHtmlEscape(chatName))</h1>\n"
        for item in exported {
            html += item.html
        }
        html += "</body></html>"
        let htmlURL = folder.appendingPathComponent("messages.html")
        try html.data(using: .utf8)?.write(to: htmlURL)
        return [jsonURL, htmlURL]
    } catch {
        return nil
    }
}

/// Exports the chat with `peerId` and presents the share sheet with the result.
public func sgExportChat(context: AccountContext, peerId: PeerId, present: @escaping (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let accountPeerId = context.account.peerId

    let showInfo: (String) -> Void = { text in
        present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: true, action: { _ in return false }))
    }
    showInfo("Экспорт чата… Это может занять время для больших чатов.")

    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    |> mapToSignal { peer -> Signal<(EnginePeer?, [Message]), NoError> in
        return sgLoadAllMessages(engine: context.engine, peerId: peerId, state: nil, collected: [], progress: { _ in })
        |> map { messages in
            return (peer, messages)
        }
    }
    |> deliverOn(Queue.concurrentDefaultQueue())
    |> map { peer, messages -> (Int, [URL]?) in
        guard let peer = peer else {
            return (0, nil)
        }
        return (messages.count, sgWriteExport(chatPeer: peer._asPeer(), accountPeerId: accountPeerId, messages: messages))
    }
    |> deliverOnMainQueue).startStandalone(next: { count, urls in
        guard let urls = urls else {
            showInfo("Не удалось экспортировать чат.")
            return
        }
        showInfo("Готово: \(count) сообщений.")
        let activityController = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        context.sharedContext.applicationBindings.presentNativeController(activityController)
    })
}
