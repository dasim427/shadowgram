import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// Shadowgram: settings for the features Shadowgram adds on top of AyuGram.

private enum SGExtrasSection: Int32 {
    case fakePhone
    case polls
    case export
}

private enum SGExtrasEntry: ItemListNodeEntry {
    case fakePhoneHeader(String)
    case fakePhoneToggle(String, Bool)
    case fakePhoneNumber(String, String)
    case fakePhoneInfo(String)
    case pollsHeader(String)
    case pollPeekToggle(String, Bool)
    case pollPeekInfo(String)
    case exportHeader(String)
    case exportInfo(String)

    var section: ItemListSectionId {
        switch self {
        case .fakePhoneHeader, .fakePhoneToggle, .fakePhoneNumber, .fakePhoneInfo:
            return SGExtrasSection.fakePhone.rawValue
        case .pollsHeader, .pollPeekToggle, .pollPeekInfo:
            return SGExtrasSection.polls.rawValue
        case .exportHeader, .exportInfo:
            return SGExtrasSection.export.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
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
        }
    }

    static func <(lhs: SGExtrasEntry, rhs: SGExtrasEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGExtrasArguments
        switch self {
        case let .fakePhoneHeader(text), let .pollsHeader(text), let .exportHeader(text):
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
        case let .fakePhoneInfo(text), let .pollPeekInfo(text), let .exportInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class SGExtrasArguments {
    let toggleFakePhone: (Bool) -> Void
    let updateFakePhone: (String) -> Void
    let togglePollPeek: (Bool) -> Void

    init(toggleFakePhone: @escaping (Bool) -> Void, updateFakePhone: @escaping (String) -> Void, togglePollPeek: @escaping (Bool) -> Void) {
        self.toggleFakePhone = toggleFakePhone
        self.updateFakePhone = updateFakePhone
        self.togglePollPeek = togglePollPeek
    }
}

private struct SGExtrasState: Equatable {
    var fakePhoneEnabled: Bool
    var fakePhoneNumber: String
    var pollPeekEnabled: Bool

    static func current() -> SGExtrasState {
        let manager = SGExtrasManager.shared
        return SGExtrasState(fakePhoneEnabled: manager.fakePhoneEnabled, fakePhoneNumber: manager.fakePhoneNumber, pollPeekEnabled: manager.pollPeekEnabled)
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
    return entries
}

public func sgExtrasController(context: AccountContext) -> ViewController {
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
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Shadowgram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: sgExtrasEntries(state: state), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
