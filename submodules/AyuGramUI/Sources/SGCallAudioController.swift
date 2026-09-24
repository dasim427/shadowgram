import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import TgVoipWebrtc

// Shadowgram: voice and sounds in calls — a real-time voice preset, the silent
// microphone and the soundpad. Everything here takes effect in a call that is already
// running: minimize the call screen, open this page and tap.

private enum SGCallAudioEntry: ItemListNodeEntry {
    case header(Int32, String)
    case voice(Int32, String, Bool, Int)
    case silentMic(Int32, Bool)
    case sound(Int32, SGSound, Bool)
    case volume(Int32, String, Bool, Int)
    case action(Int32, String, Int)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case .header(let id, _), .voice(let id, _, _, _), .silentMic(let id, _), .sound(let id, _, _), .volume(let id, _, _, _), .action(let id, _, _), .info(let id, _):
            return id / 100
        }
    }

    var stableId: Int32 {
        switch self {
        case .header(let id, _), .voice(let id, _, _, _), .silentMic(let id, _), .sound(let id, _, _), .volume(let id, _, _, _), .action(let id, _, _), .info(let id, _):
            return id
        }
    }

    static func <(lhs: SGCallAudioEntry, rhs: SGCallAudioEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGCallAudioArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .voice(_, title, checked, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setVoice(value)
            })
        case let .silentMic(_, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Тихий микрофон", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setSilent(value)
            })
        case let .sound(_, sound, isUser):
            return ItemListDisclosureItem(presentationData: presentationData, title: sound.title, label: isUser ? "свой" : "", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.play(sound)
            })
        case let .volume(_, title, checked, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.setVolume(value)
            })
        case let .action(_, title, kind):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: kind == 2 ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.performAction(kind)
            })
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class SGCallAudioArguments {
    let setVoice: (Int) -> Void
    let setSilent: (Bool) -> Void
    let play: (SGSound) -> Void
    let setVolume: (Int) -> Void
    let performAction: (Int) -> Void

    init(setVoice: @escaping (Int) -> Void, setSilent: @escaping (Bool) -> Void, play: @escaping (SGSound) -> Void, setVolume: @escaping (Int) -> Void, performAction: @escaping (Int) -> Void) {
        self.setVoice = setVoice
        self.setSilent = setSilent
        self.play = play
        self.setVolume = setVolume
        self.performAction = performAction
    }
}

private struct SGCallAudioState: Equatable {
    var voice: Int
    var silent: Bool
    var volume: Int
    var userSounds: [SGSound]
    var capturedChunks: Int
    var processedChunks: Int

    static func current() -> SGCallAudioState {
        return SGCallAudioState(voice: SGCallAudioEffects.voicePreset().rawValue, silent: SGCallAudioEffects.silentMicrophone(), volume: Int((SGCallAudioEffects.soundVolume() * 100.0).rounded()), userSounds: sgUserSounds(), capturedChunks: SGCallAudioEffects.capturedChunkCount(), processedChunks: SGCallAudioEffects.processedChunkCount())
    }
}

private let sgVoiceTitles: [(String, SGCallVoicePreset)] = [
    ("Мой голос", .off),
    ("Мужской", .male),
    ("Женский", .female),
    ("Детский", .child),
    ("Низкий", .deep),
    ("Аноним (как в новостях)", .anonymous),
    ("Робот", .robot),
    ("Телефон", .telephone)
]

private func sgCallAudioEntries(state: SGCallAudioState) -> [SGCallAudioEntry] {
    var entries: [SGCallAudioEntry] = []
    entries.append(.header(0, "ГОЛОС В ЗВОНКЕ"))
    var id: Int32 = 1
    for (title, preset) in sgVoiceTitles {
        entries.append(.voice(id, title, state.voice == preset.rawValue, preset.rawValue))
        id += 1
    }
    entries.append(.info(50, "Голос меняется прямо во время звонка, собеседник слышит уже изменённый. Действует на все звонки, пока не вернёшь «Мой голос»."))

    entries.append(.header(100, "МИКРОФОН"))
    entries.append(.silentMic(101, state.silent))
    entries.append(.info(102, "Собеседник слышит тишину, но у него не появляется отметка «микрофон выключен». Звуки саундпада при этом всё равно слышны."))

    entries.append(.header(200, "САУНДПАД"))
    id = 201
    for sound in sgBuiltInSounds {
        entries.append(.sound(id, sound, false))
        id += 1
    }
    for sound in state.userSounds.prefix(60) {
        entries.append(.sound(id, sound, true))
        id += 1
    }
    entries.append(.action(290, "Остановить звук", 0))
    entries.append(.info(291, "Нажми на звук — он прозвучит в текущем звонке, собеседник его услышит. Во время звонка сверни экран звонка и открой этот раздел."))

    entries.append(.header(300, "ГРОМКОСТЬ ЗВУКОВ"))
    id = 301
    for value in [30, 50, 80, 100] {
        entries.append(.volume(id, "\(value)%", state.volume == value, value))
        id += 1
    }

    entries.append(.header(400, "СВОИ ЗВУКИ"))
    entries.append(.action(401, "Добавить звук из файлов", 1))
    if !state.userSounds.isEmpty {
        entries.append(.action(402, "Удалить свой звук", 2))
    }
    entries.append(.info(403, "Подойдут MP3, M4A, WAV и другие аудиофайлы, до 30 секунд — длиннее обрежется."))

    entries.append(.header(500, "СОСТОЯНИЕ"))
    entries.append(.info(501, "Звук микрофона в звонках: получено \(state.capturedChunks), обработано \(state.processedChunks). Во время звонка первое число должно расти каждую секунду; второе растёт, когда включён голос, тихий микрофон или играет звук."))
    return entries
}

public func sgCallAudioController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(SGCallAudioState.current(), ignoreRepeated: true)
    let refresh: () -> Void = {
        statePromise.set(SGCallAudioState.current())
    }
    var hostControllerImpl: (() -> UIViewController?)?

    let showMessage: (String) -> Void = { text in
        guard let host = hostControllerImpl?() else {
            return
        }
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default, handler: nil))
        host.present(alert, animated: true, completion: nil)
    }

    let arguments = SGCallAudioArguments(setVoice: { value in
        SGCallAudioEffects.setVoicePreset(SGCallVoicePreset(rawValue: value) ?? .off)
        refresh()
    }, setSilent: { value in
        SGCallAudioEffects.setSilentMicrophone(value)
        refresh()
    }, play: { sound in
        if !sgPlaySound(sound) {
            showMessage("Не удалось прочитать этот звук.")
        }
    }, setVolume: { value in
        SGCallAudioEffects.setSoundVolume(Float(value) / 100.0)
        refresh()
    }, performAction: { kind in
        guard let host = hostControllerImpl?() else {
            return
        }
        switch kind {
        case 0:
            sgStopSound()
        case 1:
            if #available(iOS 14.0, *) {
                SGSoundFilePicker.present(from: host, completion: { success in
                    if !success {
                        showMessage("Не удалось добавить звук: файл не читается как аудио.")
                    }
                    refresh()
                })
            }
        default:
            let sheet = UIAlertController(title: "Удалить свой звук", message: nil, preferredStyle: .actionSheet)
            for sound in sgUserSounds() {
                sheet.addAction(UIAlertAction(title: sound.title, style: .destructive, handler: { _ in
                    sgDeleteSound(sound)
                    refresh()
                }))
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
            sheet.popoverPresentationController?.sourceView = host.view
            host.present(sheet, animated: true, completion: nil)
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Голос и звуки"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: sgCallAudioEntries(state: state), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.didAppear = { _ in
        refresh()
    }
    hostControllerImpl = { [weak controller] in
        return controller
    }
    // Keep the status counters live while the page is open.
    let _ = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak controller] timer in
        if controller == nil {
            timer.invalidate()
        } else {
            refresh()
        }
    })
    return controller
}
