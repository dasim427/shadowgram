import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import TelegramUIPreferences

// Shadowgram: settings for the features Shadowgram adds on top of AyuGram.

private enum SGExtrasSection: Int32 {
    case fakePhone
    case polls
    case export
    case tools
    case messages
    case privacy
    case calls
}

private enum SGExtrasEntry: ItemListNodeEntry {
    case toolsHeader(String)
    case voiceMorpher(String, String)
    case deviceSpoof(String, String)
    case shadowTheme(String)
    case shadowThemeInfo(String)
    case fakePhoneHeader(String)
    case fakePhoneToggle(String, Bool)
    case fakePhoneNumber(String, String)
    case fakePhoneInfo(String)
    case pollsHeader(String)
    case pollPeekToggle(String, Bool)
    case pollPeekInfo(String)
    case exportHeader(String)
    case exportInfo(String)
    case tweakHeader(Int32, Int32, String)
    case tweakToggle(Int32, Int32, String, SGToggle, Bool)
    case tweakInfo(Int32, Int32, String)
    case replacementRules(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case .toolsHeader, .voiceMorpher, .deviceSpoof, .shadowTheme, .shadowThemeInfo:
            return SGExtrasSection.tools.rawValue
        case .fakePhoneHeader, .fakePhoneToggle, .fakePhoneNumber, .fakePhoneInfo:
            return SGExtrasSection.fakePhone.rawValue
        case .pollsHeader, .pollPeekToggle, .pollPeekInfo:
            return SGExtrasSection.polls.rawValue
        case .exportHeader, .exportInfo:
            return SGExtrasSection.export.rawValue
        case let .tweakHeader(_, section, _), let .tweakToggle(_, section, _, _, _), let .tweakInfo(_, section, _), let .replacementRules(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case .toolsHeader:
            return 100
        case .voiceMorpher:
            return 101
        case .deviceSpoof:
            return 102
        case .shadowTheme:
            return 103
        case .shadowThemeInfo:
            return 104
        case .fakePhoneHeader:
            return 0
        case .fakePhoneToggle:
            return 1
        case .fakePhoneNumber:
            return 2
        case .fakePhoneInfo:
            return 3
        case .pollsHeader:
            return 10
        case .pollPeekToggle:
            return 11
        case .pollPeekInfo:
            return 12
        case .exportHeader:
            return 20
        case .exportInfo:
            return 21
        case let .tweakHeader(id, _, _), let .tweakToggle(id, _, _, _, _), let .tweakInfo(id, _, _), let .replacementRules(id, _, _):
            return id
        }
    }

    static func <(lhs: SGExtrasEntry, rhs: SGExtrasEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGExtrasArguments
        switch self {
        case let .voiceMorpher(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openVoiceMorpher()
            })
        case let .deviceSpoof(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openDeviceSpoof()
            })
        case let .shadowTheme(title):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.applyShadowTheme()
            })
        case let .toolsHeader(text), let .fakePhoneHeader(text), let .pollsHeader(text), let .exportHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .fakePhoneToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleFakePhone(value)
            })
        case let .fakePhoneNumber(placeholder, text):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "+"), text: text, placeholder: placeholder, type: .number, sectionId: self.section, textUpdated: { value in
                arguments.updateFakePhone(value)
            }, action: {})
        case let .pollPeekToggle(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.togglePollPeek(value)
            })
        case let .shadowThemeInfo(text), let .fakePhoneInfo(text), let .pollPeekInfo(text), let .exportInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .tweakHeader(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .tweakToggle(_, _, title, toggle, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setToggle(toggle, value)
            })
        case let .tweakInfo(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .replacementRules(_, _, text):
            return ItemListMultilineInputItem(presentationData: presentationData, text: text, placeholder: "спс = спасибо", maxLength: nil, sectionId: self.section, style: .blocks, capitalization: false, autocorrection: false, textUpdated: { value in
                arguments.updateReplacementRules(value)
            })
        }
    }
}

private final class SGExtrasArguments {
    let toggleFakePhone: (Bool) -> Void
    let updateFakePhone: (String) -> Void
    let togglePollPeek: (Bool) -> Void
    let openVoiceMorpher: () -> Void
    let openDeviceSpoof: () -> Void
    let applyShadowTheme: () -> Void
    let setToggle: (SGToggle, Bool) -> Void
    let updateReplacementRules: (String) -> Void

    init(toggleFakePhone: @escaping (Bool) -> Void, updateFakePhone: @escaping (String) -> Void, togglePollPeek: @escaping (Bool) -> Void, openVoiceMorpher: @escaping () -> Void, openDeviceSpoof: @escaping () -> Void, applyShadowTheme: @escaping () -> Void, setToggle: @escaping (SGToggle, Bool) -> Void, updateReplacementRules: @escaping (String) -> Void) {
        self.setToggle = setToggle
        self.updateReplacementRules = updateReplacementRules
        self.toggleFakePhone = toggleFakePhone
        self.updateFakePhone = updateFakePhone
        self.togglePollPeek = togglePollPeek
        self.openVoiceMorpher = openVoiceMorpher
        self.openDeviceSpoof = openDeviceSpoof
        self.applyShadowTheme = applyShadowTheme
    }
}

private struct SGExtrasState: Equatable {
    var fakePhoneEnabled: Bool
    var fakePhoneNumber: String
    var pollPeekEnabled: Bool
    var voiceMorpherLabel: String
    var deviceSpoofEnabled: Bool
    var enabledToggles: Set<String>
    var replacementRules: String

    static func current() -> SGExtrasState {
        let manager = SGExtrasManager.shared
        let voiceMorpherLabel = VoiceMorpherManager.shared.isEnabled ? VoiceMorpherManager.shared.selectedPreset.name : "Выкл"
        let enabledToggles = Set(SGToggle.allCases.filter { manager.isOn($0) }.map { $0.rawValue })
        return SGExtrasState(fakePhoneEnabled: manager.fakePhoneEnabled, fakePhoneNumber: manager.fakePhoneNumber, pollPeekEnabled: manager.pollPeekEnabled, voiceMorpherLabel: voiceMorpherLabel, deviceSpoofEnabled: DeviceSpoofManager.shared.isEnabled, enabledToggles: enabledToggles, replacementRules: manager.textReplacementRulesText)
    }

    func isOn(_ toggle: SGToggle) -> Bool {
        return self.enabledToggles.contains(toggle.rawValue)
    }
}

private func sgExtrasEntries(state: SGExtrasState) -> [SGExtrasEntry] {
    var entries: [SGExtrasEntry] = []
    entries.append(.fakePhoneHeader("ФЕЙКОВЫЙ НОМЕР"))
    entries.append(.fakePhoneToggle("Показывать фейковый номер", state.fakePhoneEnabled))
    if state.fakePhoneEnabled {
        entries.append(.fakePhoneNumber("79991234567", state.fakePhoneNumber))
    }
    entries.append(.fakePhoneInfo("Вместо твоего номера в профиле и настройках будет показан этот. Номер меняется только на экране — удобно для скриншотов и стримов. Изменения видны после повторного открытия настроек."))

    entries.append(.pollsHeader("ОПРОСЫ"))
    entries.append(.pollPeekToggle("Подсматривать результаты", state.pollPeekEnabled))
    entries.append(.pollPeekInfo("В меню анонимного опроса (долгое нажатие) появится «Подсмотреть результаты»: приложение голосует, запоминает проценты и сразу отменяет голос. Работает только там, где голос можно отменить; викторины не поддерживаются."))

    entries.append(.exportHeader("ЭКСПОРТ ЧАТОВ"))
    entries.append(.exportInfo("Откройте профиль чата → «⋯» → «Экспорт чата». Сохраняется result.json в формате Telegram Desktop и messages.html."))

    entries.append(.toolsHeader("ИНСТРУМЕНТЫ"))
    entries.append(.voiceMorpher("Голосовой двойник", state.voiceMorpherLabel))
    entries.append(.deviceSpoof("Подмена устройства", state.deviceSpoofEnabled ? "Вкл" : "Выкл"))
    entries.append(.shadowTheme("Применить тему Shadow"))
    entries.append(.shadowThemeInfo("Тёмная тема в цветах Shadowgram: фиолетовые акценты и пузыри, анимированный фон. Вернуть обычную — Настройки → Оформление."))

    let messages = SGExtrasSection.messages.rawValue
    entries.append(.tweakHeader(200, messages, "СООБЩЕНИЯ"))
    entries.append(.tweakToggle(201, messages, "Скрыть «изменено»", .hideEditedMark, state.isOn(.hideEditedMark)))
    entries.append(.tweakToggle(202, messages, "Скрыть просмотры в каналах", .hideChannelViews, state.isOn(.hideChannelViews)))
    entries.append(.tweakToggle(203, messages, "Скрывать приветственный стикер", .hideGreetingSticker, state.isOn(.hideGreetingSticker)))
    entries.append(.tweakToggle(204, messages, "Анти-капс", .antiCaps, state.isOn(.antiCaps)))
    entries.append(.tweakInfo(205, messages, "Анти-капс: сообщение, набранное капсом, уходит в обычном виде — «ПРИВЕТ ВСЕМ» → «Привет всем»."))
    entries.append(.tweakToggle(206, messages, "Автозамена текста", .textReplacement, state.isOn(.textReplacement)))
    if state.isOn(.textReplacement) {
        entries.append(.replacementRules(207, messages, state.replacementRules))
    }
    entries.append(.tweakInfo(208, messages, "По правилу на строку: «спс = спасибо». Заменяются целые слова без учёта регистра в момент отправки. В сообщениях с форматированием автозамена не срабатывает."))

    let privacy = SGExtrasSection.privacy.rawValue
    entries.append(.tweakHeader(300, privacy, "ПРОФИЛИ"))
    entries.append(.tweakToggle(301, privacy, "Точное время выхода", .exactLastSeen, state.isOn(.exactLastSeen)))
    entries.append(.tweakInfo(302, privacy, "К «был(а) 2 часа назад» дописывается время выхода: «(14:05)»."))

    let calls = SGExtrasSection.calls.rawValue
    entries.append(.tweakHeader(400, calls, "ЗВОНКИ"))
    entries.append(.tweakToggle(401, calls, "Не спрашивать оценку звонка", .noCallRating, state.isOn(.noCallRating)))
    return entries
}

// Tinted night theme with a violet accent (tints the backgrounds), violet bubbles and a dark animated gradient
private let sgShadowThemeWallpaper: TelegramWallpaper = .gradient(TelegramWallpaper.Gradient(
    id: nil,
    colors: [0x1c1238, 0x0b0818, 0x2a1752, 0x120c28],
    settings: WallpaperSettings()
))

private let sgShadowThemeAccentColor = PresentationThemeAccentColor(
    index: 777,
    baseColor: .custom,
    accentColor: 0x8b6cff,
    bubbleColors: [0x7b5cff, 0x4a2fc0],
    wallpaper: sgShadowThemeWallpaper
)

private func sgApplyShadowTheme(context: AccountContext) {
    let _ = updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
        var updated = current
        let themeReference: PresentationThemeReference = .builtin(.nightAccent)
        updated.theme = themeReference
        updated.themeSpecificAccentColors[themeReference.index] = sgShadowThemeAccentColor
        updated.themeSpecificChatWallpapers[coloredThemeIndex(reference: themeReference, accentColor: sgShadowThemeAccentColor)] = sgShadowThemeWallpaper
        updated.automaticThemeSwitchSetting.theme = themeReference
        return updated
    }).start()
}

public func sgExtrasController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let statePromise = ValuePromise(SGExtrasState.current(), ignoreRepeated: true)
    let refresh: () -> Void = {
        statePromise.set(SGExtrasState.current())
    }

    let arguments = SGExtrasArguments(toggleFakePhone: { value in
        SGExtrasManager.shared.fakePhoneEnabled = value
        refresh()
    }, updateFakePhone: { value in
        SGExtrasManager.shared.fakePhoneNumber = value
        refresh()
    }, togglePollPeek: { value in
        SGExtrasManager.shared.pollPeekEnabled = value
        refresh()
    }, openVoiceMorpher: {
        pushControllerImpl?(voiceMorpherController(context: context))
    }, openDeviceSpoof: {
        pushControllerImpl?(deviceSpoofController(context: context))
    }, applyShadowTheme: {
        sgApplyShadowTheme(context: context)
    }, setToggle: { toggle, value in
        SGExtrasManager.shared.setOn(toggle, value)
        refresh()
    }, updateReplacementRules: { value in
        SGExtrasManager.shared.textReplacementRulesText = value
        refresh()
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Shadowgram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: sgExtrasEntries(state: state), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.didAppear = { _ in
        refresh()
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}
