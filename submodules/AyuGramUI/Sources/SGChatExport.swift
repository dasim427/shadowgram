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
// to the system share sheet. Media is optional: when included it is downloaded into the
// same folders Telegram Desktop uses, otherwise listed with its "File not included" placeholder.

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

private func sgExportMessage(_ message: Message, mediaPath: String?) -> SGExportedMessage {
    var json: [String: Any] = [:]
    json["id"] = Int(message.id.id)

    var isService = false
    var mediaDescription: String?
    for media in message.media {
        if media is TelegramMediaAction {
            isService = true
        } else if let image = media as? TelegramMediaImage {
            json["photo"] = mediaPath ?? sgFileNotIncluded
            if let largest = image.representations.last {
                json["width"] = Int(largest.dimensions.width)
                json["height"] = Int(largest.dimensions.height)
            }
            mediaDescription = "Фото"
        } else if let file = media as? TelegramMediaFile {
            json["file"] = mediaPath ?? sgFileNotIncluded
            if let fileName = file.fileName {
                json["file_name"] = fileName
            }
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
        if let mediaPath = mediaPath, json["photo"] != nil {
            html += "<div class=\"media\"><a href=\"\(mediaPath)\"><img src=\"\(mediaPath)\"></a></div>"
        } else if let mediaPath = mediaPath {
            html += "<div class=\"media\"><a href=\"\(mediaPath)\">[\(mediaDescription)]</a></div>"
        } else {
            html += "<div class=\"media\">[\(mediaDescription)]</div>"
        }
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

private let sgExportMaxFileSize: Int64 = 50 * 1024 * 1024

private struct SGMediaTask {
    let messageId: MessageId
    let resource: MediaResource
    let reference: MediaResourceReference
    let contentType: MediaResourceUserContentType
    let relativePath: String
}

/// Picks the file Telegram Desktop would export for this message, laid out in the same
/// folders (photos/, files/, voice_messages/, round_video_messages/, video_files/).
private func sgMediaTask(for message: Message) -> SGMediaTask? {
    let messageReference = MessageReference(message)
    for media in message.media {
        if let image = media as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
            let reference = AnyMediaReference.message(message: messageReference, media: image).resourceReference(representation.resource)
            return SGMediaTask(messageId: message.id, resource: representation.resource, reference: reference, contentType: .image, relativePath: "photos/photo_\(message.id.id).jpg")
        } else if let file = media as? TelegramMediaFile {
            if file.isSticker || file.isAnimated {
                return nil
            }
            if let size = file.size, size > sgExportMaxFileSize {
                return nil
            }
            let folder: String
            let defaultName: String
            if file.isInstantVideo {
                folder = "round_video_messages"
                defaultName = "file_\(message.id.id).mp4"
            } else if file.isVoice {
                folder = "voice_messages"
                defaultName = "audio_\(message.id.id).ogg"
            } else if file.isVideo {
                folder = "video_files"
                defaultName = "video_\(message.id.id).mp4"
            } else {
                folder = "files"
                defaultName = "file_\(message.id.id)"
            }
            var name = defaultName
            if let fileName = file.fileName, !fileName.isEmpty {
                let safe = fileName.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
                name = "\(message.id.id)_\(safe)"
            }
            let reference = AnyMediaReference.message(message: messageReference, media: file).resourceReference(file.resource)
            return SGMediaTask(messageId: message.id, resource: file.resource, reference: reference, contentType: MediaResourceUserContentType(file: file), relativePath: "\(folder)/\(name)")
        }
    }
    return nil
}

private func sgDownloadMedia(context: AccountContext, peerId: PeerId, task: SGMediaTask, folder: URL) -> Signal<Bool, NoError> {
    let mediaBox = context.account.postbox.mediaBox
    let destination = folder.appendingPathComponent(task.relativePath)
    let download = Signal<Bool, NoError> { subscriber in
        let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(peerId), userContentType: task.contentType, reference: task.reference).start()
        let data = (mediaBox.resourceData(task.resource)
        |> filter { $0.complete }
        |> take(1)).start(next: { data in
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(atPath: data.path, toPath: destination.path)
                subscriber.putNext(true)
            } catch {
                subscriber.putNext(false)
            }
            subscriber.putCompletion()
        })
        return ActionDisposable {
            fetch.dispose()
            data.dispose()
        }
    }
    return download
    |> timeout(120.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(false))
}

private func sgDownloadAllMedia(context: AccountContext, peerId: PeerId, tasks: [SGMediaTask], index: Int, folder: URL, done: [MessageId: String]) -> Signal<[MessageId: String], NoError> {
    if index >= tasks.count {
        return .single(done)
    }
    let task = tasks[index]
    return sgDownloadMedia(context: context, peerId: peerId, task: task, folder: folder)
    |> mapToSignal { success -> Signal<[MessageId: String], NoError> in
        var updated = done
        if success {
            updated[task.messageId] = task.relativePath
        }
        return sgDownloadAllMedia(context: context, peerId: peerId, tasks: tasks, index: index + 1, folder: folder, done: updated)
    }
}

private func sgMakeExportFolder() -> URL? {
    let folderName = "ChatExport_\(sgExportDateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-"))"
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(folderName, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    } catch {
        return nil
    }
}

private func sgWriteExport(chatPeer: Peer, accountPeerId: PeerId, messages: [Message], mediaPaths: [MessageId: String], folder: URL) -> Bool {
    let sorted = messages.sorted(by: { $0.id.id < $1.id.id })
    let exported = sorted.map { sgExportMessage($0, mediaPath: mediaPaths[$0.id]) }

    let chatName = sgPeerName(chatPeer)
    let root: [String: Any] = [
        "name": chatName,
        "type": sgChatType(chatPeer, accountPeerId: accountPeerId),
        "id": chatPeer.id.id._internalGetInt64Value(),
        "messages": exported.map { $0.json }
    ]

    do {
        let jsonData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: folder.appendingPathComponent("result.json"))

        var html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(sgHtmlEscape(chatName))</title><style>"
        html += "body{font-family:-apple-system,Helvetica,Arial,sans-serif;background:#e7ebf0;margin:0;padding:16px}"
        html += "h1{font-size:20px}.message{background:#fff;border-radius:10px;padding:8px 12px;margin:6px 0;max-width:720px}"
        html += ".meta{font-size:13px;color:#70777b;margin-bottom:4px}.from{color:#3892db;font-weight:600}"
        html += ".media,.forwarded,.reply{font-size:13px;color:#70777b}.media img{max-width:320px;max-height:320px;border-radius:6px}"
        html += ".text{font-size:15px;white-space:normal;word-wrap:break-word}.service{color:#70777b;font-style:italic}"
        html += "</style></head><body><h1>\(sgHtmlEscape(chatName))</h1>\n"
        for item in exported {
            html += item.html
        }
        html += "</body></html>"
        try html.data(using: .utf8)?.write(to: folder.appendingPathComponent("messages.html"))
        return true
    } catch {
        return false
    }
}

private func sgRunExport(context: AccountContext, peerId: PeerId, includeMedia: Bool, showInfo: @escaping (String) -> Void) {
    let accountPeerId = context.account.peerId
    guard let folder = sgMakeExportFolder() else {
        showInfo("Не удалось экспортировать чат.")
        return
    }
    showInfo(includeMedia ? "Экспорт чата с медиа… Это может занять несколько минут." : "Экспорт чата… Это может занять время для больших чатов.")

    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    |> mapToSignal { peer -> Signal<(EnginePeer?, [Message], [MessageId: String]), NoError> in
        return sgLoadAllMessages(engine: context.engine, peerId: peerId, state: nil, collected: [], progress: { _ in })
        |> mapToSignal { messages -> Signal<(EnginePeer?, [Message], [MessageId: String]), NoError> in
            if !includeMedia {
                return .single((peer, messages, [:]))
            }
            let tasks = messages.sorted(by: { $0.id.id < $1.id.id }).compactMap { sgMediaTask(for: $0) }
            return sgDownloadAllMedia(context: context, peerId: peerId, tasks: tasks, index: 0, folder: folder, done: [:])
            |> map { mediaPaths -> (EnginePeer?, [Message], [MessageId: String]) in
                return (peer, messages, mediaPaths)
            }
        }
    }
    |> deliverOn(Queue.concurrentDefaultQueue())
    |> map { peer, messages, mediaPaths -> (Int, Int, Bool) in
        guard let peer = peer else {
            return (0, 0, false)
        }
        let success = sgWriteExport(chatPeer: peer._asPeer(), accountPeerId: accountPeerId, messages: messages, mediaPaths: mediaPaths, folder: folder)
        return (messages.count, mediaPaths.count, success)
    }
    |> deliverOnMainQueue).startStandalone(next: { count, mediaCount, success in
        guard success else {
            showInfo("Не удалось экспортировать чат.")
            return
        }
        showInfo(includeMedia ? "Готово: \(count) сообщений, \(mediaCount) файлов." : "Готово: \(count) сообщений.")
        let activityController = UIActivityViewController(activityItems: [folder], applicationActivities: nil)
        context.sharedContext.applicationBindings.presentNativeController(activityController)
    })
}

/// Asks whether to include media, exports the chat with `peerId` and presents the share
/// sheet with the export folder.
public func sgExportChat(context: AccountContext, peerId: PeerId, present: @escaping (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let showInfo: (String) -> Void = { text in
        present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: true, action: { _ in return false }))
    }

    let actionSheet = ActionSheetController(presentationData: presentationData)
    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: [
            ActionSheetTextItem(title: "Экспорт в формате Telegram Desktop (result.json + messages.html)"),
            ActionSheetButtonItem(title: "Только текст", action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                sgRunExport(context: context, peerId: peerId, includeMedia: false, showInfo: showInfo)
            }),
            ActionSheetButtonItem(title: "С медиа (файлы до 50 МБ)", action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                sgRunExport(context: context, peerId: peerId, includeMedia: true, showInfo: showInfo)
            })
        ]),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])
    ])
    present(actionSheet)
}
