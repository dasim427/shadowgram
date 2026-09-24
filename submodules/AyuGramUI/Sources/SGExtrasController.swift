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
    case round
    case appearance
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
    case roundOption(Int32, Int32, String, Bool, Int, Int)
    case bubbleTails(Int32, Int32, String, Bool)
    case tweakAction(Int32, Int32, String, Int)

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
        case let .tweakHeader(_, section, _), let .tweakToggle(_, section, _, _, _), let .tweakInfo(_, section, _), let .replacementRules(_, section, _), let .roundOption(_, section, _, _, _, _), let .bubbleTails(_, section, _, _), let .tweakAction(_, section, _, _):
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
        case let .tweakHeader(id, _, _), let .tweakToggle(id, _, _, _, _), let .tweakInfo(id, _, _), let .replacementRules(id, _, _), let .roundOption(id, _, _, _, _, _), let .bubbleTails(id, _, _, _), let .tweakAction(id, _, _, _):
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
        case let .roundOption(_, _, title, checked, kind, value):
            return ItemListCheckboxItem(presentationData: presentationData, title: title, style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectRoundOption(kind, value)
            })
        case let .bubbleTails(_, _, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setBubbleTails(value)
            })
        case let .tweakAction(_, _, title, kind):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.performAction(kind)
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
    let selectRoundOption: (Int, Int) -> Void
    let setBubbleTails: (Bool) -> Void
    let performAction: (Int) -> Void

    init(toggleFakePhone: @escaping (Bool) -> Void, updateFakePhone: @escaping (String) -> Void, togglePollPeek: @escaping (Bool) -> Void, openVoiceMorpher: @escaping () -> Void, openDeviceSpoof: @escaping () -> Void, applyShadowTheme: @escaping () -> Void, setToggle: @escaping (SGToggle, Bool) -> Void, updateReplacementRules: @escaping (String) -> Void, selectRoundOption: @escaping (Int, Int) -> Void, setBubbleTails: @escaping (Bool) -> Void, performAction: @escaping (Int) -> Void) {
        self.performAction = performAction
        self.setBubbleTails = setBubbleTails
        self.selectRoundOption = selectRoundOption
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
    var roundResolution: Int32
    var roundBitrate: Int
    var checkColor: Int
    var bubbleRadius: Int32
    var bubbleTails: Bool
    var bubbleWidth: Int
    var chatListAvatar: Int
    var bubbleOpacity: Int
    var bubbleOutline: Int
    var customFontName: String?
    var hasChatBackground: Bool
    var gifOpacity: Int

    static func current(context: AccountContext) -> SGExtrasState {
        let bubbleSettings = context.sharedContext.currentPresentationData.with { $0 }.chatBubbleCorners
        let manager = SGExtrasManager.shared
        let voiceMorpherLabel = VoiceMorpherManager.shared.isEnabled ? VoiceMorpherManager.shared.selectedPreset.name : "Выкл"
        let enabledToggles = Set(SGToggle.allCases.filter { manager.isOn($0) }.map { $0.rawValue })
        return SGExtrasState(fakePhoneEnabled: manager.fakePhoneEnabled, fakePhoneNumber: manager.fakePhoneNumber, pollPeekEnabled: manager.pollPeekEnabled, voiceMorpherLabel: voiceMorpherLabel, deviceSpoofEnabled: DeviceSpoofManager.shared.isEnabled, enabledToggles: enabledToggles, replacementRules: manager.textReplacementRulesText, roundResolution: manager.roundResolution, roundBitrate: manager.roundBitrateKbps, checkColor: manager.checkColorRGB, bubbleRadius: Int32(bubbleSettings.mainRadius), bubbleTails: bubbleSettings.hasTails, bubbleWidth: manager.bubbleWidthPercent, chatListAvatar: manager.chatListAvatarPercent, bubbleOpacity: manager.bubbleOpacityPercent, bubbleOutline: manager.bubbleOutlineRGB, customFontName: sgCustomFontName(), hasChatBackground: sgHasChatBackground(), gifOpacity: manager.gifBackgroundOpacityPercent)
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

    let round = SGExtrasSection.round.rawValue
    entries.append(.tweakHeader(500, round, "КРУЖКИ — РАЗРЕШЕНИЕ"))
    var roundId: Int32 = 501
    for side in SGExtrasManager.roundResolutionOptions {
        let title = side == 400 ? "400 × 400 (стандарт)" : "\(side) × \(side)"
        entries.append(.roundOption(roundId, round, title, state.roundResolution == side, 0, Int(side)))
        roundId += 1
    }
    entries.append(.tweakInfo(510, round, "По умолчанию Telegram снимает кружки 400 × 400, поэтому они выглядят размыто. Большее разрешение даёт более чёткую картинку, но файл весит больше."))
    entries.append(.tweakHeader(520, round, "БИТРЕЙТ"))
    roundId = 521
    for kbps in SGExtrasManager.roundBitrateOptions {
        let mbps = Double(kbps) / 1000.0
        let title = String(format: "%.0f Мбит/с", mbps) + (kbps == 1000 ? " (стандарт)" : "")
        entries.append(.roundOption(roundId, round, title, state.roundBitrate == kbps, 1, kbps))
        roundId += 1
    }
    entries.append(.tweakInfo(530, round, "Выше битрейт — меньше артефактов на движении, но файл больше. Для 640 и 800 лучше ставить от 3 Мбит/с."))
    entries.append(.tweakHeader(540, round, "ЗАПИСЬ КРУЖКОВ"))
    entries.append(.tweakToggle(541, round, "60 кадров/с", .round60fps, state.isOn(.round60fps)))
    entries.append(.tweakToggle(542, round, "HEVC (меньше вес)", .roundHEVC, state.isOn(.roundHEVC)))
    entries.append(.tweakToggle(543, round, "Начинать с задней камеры", .roundStartRear, state.isOn(.roundStartRear)))
    entries.append(.tweakToggle(544, round, "Записывать без звука", .roundMuted, state.isOn(.roundMuted)))
    entries.append(.tweakToggle(545, round, "Не останавливать музыку", .roundKeepMusic, state.isOn(.roundKeepMusic)))
    entries.append(.tweakToggle(546, round, "Сохранять копию в галерею", .roundSaveToGallery, state.isOn(.roundSaveToGallery)))
    let appearance = SGExtrasSection.appearance.rawValue
    entries.append(.tweakHeader(600, appearance, "ОФОРМЛЕНИЕ"))
    entries.append(.tweakToggle(601, appearance, "Квадратные аватарки", .squareAvatars, state.isOn(.squareAvatars)))
    entries.append(.tweakToggle(602, appearance, "Скрыть кружки сторис в списке чатов", .hideStoryRings, state.isOn(.hideStoryRings)))
    entries.append(.tweakToggle(603, appearance, "Снег в списке чатов", .snow, state.isOn(.snow)))
    entries.append(.tweakToggle(605, appearance, "Мини-аватарка отправителя в списке чатов", .senderMiniAvatars, state.isOn(.senderMiniAvatars)))
    entries.append(.tweakInfo(604, appearance, "Аватарки и кружки сторис обновятся при прокрутке или после перезапуска."))
    entries.append(.tweakHeader(610, appearance, "ПУЗЫРИ СООБЩЕНИЙ"))
    entries.append(.bubbleTails(611, appearance, "Хвостик у пузырей", state.bubbleTails))
    var appearanceId: Int32 = 612
    for radius: Int32 in [4, 8, 12, 16, 20] {
        let title = "Скругление \(radius)" + (radius == 16 ? " (стандарт)" : "")
        entries.append(.roundOption(appearanceId, appearance, title, state.bubbleRadius == radius, 3, Int(radius)))
        appearanceId += 1
    }
    entries.append(.tweakHeader(620, appearance, "ЦВЕТ ГАЛОЧЕК"))
    appearanceId = 621
    for (title, rgb) in SGExtrasManager.checkColorOptions {
        entries.append(.roundOption(appearanceId, appearance, title, state.checkColor == rgb, 2, rgb))
        appearanceId += 1
    }
    entries.append(.tweakInfo(630, appearance, "Цвет галочек на исходящих сообщениях применяется после перезапуска приложения."))
    entries.append(.tweakHeader(640, appearance, "ШИРИНА ПУЗЫРЕЙ"))
    appearanceId = 641
    for percent in SGExtrasManager.bubbleWidthOptions {
        entries.append(.roundOption(appearanceId, appearance, "\(percent)%" + (percent == 100 ? " (стандарт)" : ""), state.bubbleWidth == percent, 4, percent))
        appearanceId += 1
    }
    entries.append(.tweakHeader(650, appearance, "РАЗМЕР АВАТАРОК В СПИСКЕ ЧАТОВ"))
    appearanceId = 651
    for percent in SGExtrasManager.chatListAvatarOptions {
        entries.append(.roundOption(appearanceId, appearance, "\(percent)%" + (percent == 100 ? " (стандарт)" : ""), state.chatListAvatar == percent, 5, percent))
        appearanceId += 1
    }
    entries.append(.tweakHeader(660, appearance, "ИНТЕРФЕЙС"))
    entries.append(.tweakAction(665, appearance, "Применить AMOLED-тему (чистый чёрный)", 0))
    entries.append(.tweakToggle(661, appearance, "Скрыть разделители в списке чатов", .hideChatListSeparators, state.isOn(.hideChatListSeparators)))
    entries.append(.tweakToggle(662, appearance, "Всегда тёмная клавиатура", .darkKeyboard, state.isOn(.darkKeyboard)))
    entries.append(.tweakToggle(663, appearance, "Скруглённый шрифт", .roundedFont, state.isOn(.roundedFont)))
    entries.append(.tweakToggle(666, appearance, "Скрыть вкладку «Контакты»", .hideContactsTab, state.isOn(.hideContactsTab)))
    entries.append(.tweakHeader(700, appearance, "GIF-ФОН В ЧАТЕ"))
    entries.append(.tweakAction(701, appearance, state.hasChatBackground ? "Заменить GIF или картинку" : "Выбрать GIF или картинку", 3))
    if state.hasChatBackground {
        entries.append(.tweakToggle(702, appearance, "Показывать фон", .gifChatBackground, state.isOn(.gifChatBackground)))
        var opacityId: Int32 = 703
        for percent in SGExtrasManager.gifBackgroundOpacityOptions {
            entries.append(.roundOption(opacityId, appearance, "Непрозрачность \(percent)%", state.gifOpacity == percent, 8, percent))
            opacityId += 1
        }
        entries.append(.tweakAction(708, appearance, "Убрать фон", 4))
    }
    entries.append(.tweakInfo(709, appearance, "Фон ложится поверх обоев во всех чатах. GIF анимируется. Если чат уже был открыт, фон появится после повторного входа в него."))
    entries.append(.tweakHeader(691, appearance, "СВОЙ ШРИФТ"))
    entries.append(.tweakAction(692, appearance, "Выбрать файл шрифта (.ttf, .otf)", 1))
    if state.customFontName != nil {
        entries.append(.tweakAction(693, appearance, "Вернуть системный шрифт", 2))
    }
    entries.append(.tweakInfo(694, appearance, (state.customFontName.flatMap { "Сейчас: \($0). " } ?? "") + "Шрифт применяется к основным надписям после перезапуска. Если в файле нет кириллицы, русский текст будет системным шрифтом."))
    entries.append(.tweakHeader(670, appearance, "ПРОЗРАЧНОСТЬ ПУЗЫРЕЙ"))
    appearanceId = 671
    for percent in SGExtrasManager.bubbleOpacityOptions {
        entries.append(.roundOption(appearanceId, appearance, "\(percent)%" + (percent == 100 ? " (стандарт)" : ""), state.bubbleOpacity == percent, 6, percent))
        appearanceId += 1
    }
    entries.append(.tweakHeader(680, appearance, "ОБВОДКА ПУЗЫРЕЙ"))
    appearanceId = 681
    for (title, rgb) in SGExtrasManager.checkColorOptions {
        entries.append(.roundOption(appearanceId, appearance, rgb == 0 ? "Без обводки (как в теме)" : title, state.bubbleOutline == rgb, 7, rgb))
        appearanceId += 1
    }
    entries.append(.tweakInfo(690, appearance, "Прозрачность и обводка пузырей применяются после перезапуска. Прозрачные пузыри лучше смотрятся на обоях с картинкой. Вкладка «Контакты» скрывается после перезапуска."))
    entries.append(.tweakInfo(664, appearance, "Ширина пузырей и размер аватарок применяются к новым строкам сразу, а полностью — после перезапуска. Скруглённый шрифт (SF Rounded) включается после перезапуска."))
    entries.append(.tweakInfo(547, round,"60 кадров/с — плавнее, но сильнее грузит батарею. HEVC примерно вдвое легче H.264, но старые клиенты могут не воспроизвести такой кружок. Копия в галерею попросит доступ к Фото."))
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

// Bubble shape lives in Telegram's own theme settings, so changing it re-renders open
// chats right away. The list refreshes once the new presentation data has landed.
private func sgUpdateBubbleSettings(context: AccountContext, refresh: @escaping () -> Void, _ f: @escaping (inout PresentationChatBubbleSettings) -> Void) {
    let _ = (updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
        var updated = current
        f(&updated.chatBubbleSettings)
        return updated
    })
    |> deliverOnMainQueue).start(completed: {
        Queue.mainQueue().after(0.3, refresh)
    })
}

public func sgExtrasController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var hostControllerImpl: (() -> UIViewController?)?
    let statePromise = ValuePromise(SGExtrasState.current(context: context), ignoreRepeated: true)
    let refresh: () -> Void = {
        statePromise.set(SGExtrasState.current(context: context))
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
    }, selectRoundOption: { kind, value in
        switch kind {
        case 0:
            SGExtrasManager.shared.roundResolution = Int32(value)
        case 1:
            SGExtrasManager.shared.roundBitrateKbps = value
        case 2:
            SGExtrasManager.shared.checkColorRGB = value
        case 4:
            SGExtrasManager.shared.bubbleWidthPercent = value
        case 5:
            SGExtrasManager.shared.chatListAvatarPercent = value
        case 6:
            SGExtrasManager.shared.bubbleOpacityPercent = value
        case 7:
            SGExtrasManager.shared.bubbleOutlineRGB = value
        case 8:
            SGExtrasManager.shared.gifBackgroundOpacityPercent = value
        default:
            sgUpdateBubbleSettings(context: context, refresh: refresh) { settings in
                settings.mainRadius = Int32(value)
                settings.auxiliaryRadius = max(2, Int32(value) / 2)
            }
        }
        refresh()
    }, setBubbleTails: { value in
        sgUpdateBubbleSettings(context: context, refresh: refresh) { settings in
            settings.hasTails = value
        }
    }, performAction: { kind in
        switch kind {
        case 0:
            // Telegram's built-in "Night" theme already uses pure black backgrounds.
            let _ = updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                var updated = current
                let themeReference: PresentationThemeReference = .builtin(.night)
                updated.theme = themeReference
                updated.automaticThemeSwitchSetting.theme = themeReference
                return updated
            }).start()
        case 1:
            guard let hostController = hostControllerImpl?() else {
                return
            }
            SGFontPicker.present(from: hostController, completion: { _ in
                refresh()
            })
        case 3:
            guard let hostController = hostControllerImpl?() else {
                return
            }
            if #available(iOS 14.0, *) {
                SGBackgroundPicker.present(from: hostController, completion: { success in
                    if success {
                        SGExtrasManager.shared.setOn(.gifChatBackground, true)
                    }
                    refresh()
                })
            }
        case 4:
            sgRemoveChatBackground()
            SGExtrasManager.shared.setOn(.gifChatBackground, false)
            refresh()
        default:
            sgResetCustomFont()
            refresh()
        }
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
    hostControllerImpl = { [weak controller] in
        return controller
    }
    return controller
}
