import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: - Entry Definition

private enum DeviceSpoofSection: Int32 {
    case enable
    case profiles
    case custom
}

private enum DeviceSpoofEntry: ItemListNodeEntry {
    case enableHeader(PresentationTheme, String)
    case enableToggle(PresentationTheme, String, Bool)
    case enableInfo(PresentationTheme, String)
    case profilesHeader(PresentationTheme, String)
    case profile(PresentationTheme, Int, String, Bool)
    case customHeader(PresentationTheme, String)
    case customDeviceModel(PresentationTheme, String, String)
    case customSystemVersion(PresentationTheme, String, String)
    case customInfo(PresentationTheme, String)
    
    var section: ItemListSectionId {
        switch self {
        case .enableHeader, .enableToggle, .enableInfo:
            return DeviceSpoofSection.enable.rawValue
        case .profilesHeader, .profile:
            return DeviceSpoofSection.profiles.rawValue
        case .customHeader, .customDeviceModel, .customSystemVersion, .customInfo:
            return DeviceSpoofSection.custom.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
        case .enableHeader: return 0
        case .enableToggle: return 1
        case .enableInfo: return 2
        case .profilesHeader: return 3
        case let .profile(_, id, _, _): return 10 + Int32(id)
        case .customHeader: return 500
        case .customDeviceModel: return 501
        case .customSystemVersion: return 502
        case .customInfo: return 503
        }
    }
    
    static func ==(lhs: DeviceSpoofEntry, rhs: DeviceSpoofEntry) -> Bool {
        switch lhs {
        case let .enableHeader(lhsTheme, lhsText):
            if case let .enableHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        case let .enableToggle(lhsTheme, lhsText, lhsValue):
            if case let .enableToggle(rhsTheme, rhsText, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsText == rhsText, lhsValue == rhsValue {
                return true
            }
            return false
        case let .enableInfo(lhsTheme, lhsText):
            if case let .enableInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        case let .profilesHeader(lhsTheme, lhsText):
            if case let .profilesHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        case let .profile(lhsTheme, lhsId, lhsName, lhsSelected):
            if case let .profile(rhsTheme, rhsId, rhsName, rhsSelected) = rhs,
               lhsTheme === rhsTheme, lhsId == rhsId, lhsName == rhsName, lhsSelected == rhsSelected {
                return true
            }
            return false
        case let .customHeader(lhsTheme, lhsText):
            if case let .customHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        case let .customDeviceModel(lhsTheme, lhsTitle, lhsValue):
            if case let .customDeviceModel(rhsTheme, rhsTitle, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsValue == rhsValue {
                return true
            }
            return false
        case let .customSystemVersion(lhsTheme, lhsTitle, lhsValue):
            if case let .customSystemVersion(rhsTheme, rhsTitle, rhsValue) = rhs,
               lhsTheme === rhsTheme, lhsTitle == rhsTitle, lhsValue == rhsValue {
                return true
            }
            return false
        case let .customInfo(lhsTheme, lhsText):
            if case let .customInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                return true
            }
            return false
        }
    }
    
    static func <(lhs: DeviceSpoofEntry, rhs: DeviceSpoofEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DeviceSpoofControllerArguments
        switch self {
        case let .enableHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .enableToggle(_, text, value):
            return ItemListSwitchItem(presentationData: presentationData, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleEnabled(value)
            })
        case let .enableInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .profilesHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .profile(_, id, name, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: name, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectProfile(id)
            })
        case let .customHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .customDeviceModel(_, title, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: title), text: value, placeholder: "iPhone 14 Pro", sectionId: self.section, textUpdated: { text in
                arguments.updateCustomDeviceModel(text)
            }, action: {})
        case let .customSystemVersion(_, title, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: title), text: value, placeholder: "iOS 17.2", sectionId: self.section, textUpdated: { text in
                arguments.updateCustomSystemVersion(text)
            }, action: {})
        case let .customInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

// MARK: - Arguments

private final class DeviceSpoofControllerArguments {
    let toggleEnabled: (Bool) -> Void
    let selectProfile: (Int) -> Void
    let updateCustomDeviceModel: (String) -> Void
    let updateCustomSystemVersion: (String) -> Void
    
    init(
        toggleEnabled: @escaping (Bool) -> Void,
        selectProfile: @escaping (Int) -> Void,
        updateCustomDeviceModel: @escaping (String) -> Void,
        updateCustomSystemVersion: @escaping (String) -> Void
    ) {
        self.toggleEnabled = toggleEnabled
        self.selectProfile = selectProfile
        self.updateCustomDeviceModel = updateCustomDeviceModel
        self.updateCustomSystemVersion = updateCustomSystemVersion
    }
}

// MARK: - State

private struct DeviceSpoofControllerState: Equatable {
    var isEnabled: Bool
    var selectedProfileId: Int
    var customDeviceModel: String
    var customSystemVersion: String
}

// MARK: - Entries Builder

private func deviceSpoofControllerEntries(presentationData: PresentationData, state: DeviceSpoofControllerState) -> [DeviceSpoofEntry] {
    var entries: [DeviceSpoofEntry] = []
    
    let theme = presentationData.theme
    
    entries.append(.enableHeader(theme, "ПОДМЕНА УСТРОЙСТВА"))
    entries.append(.enableToggle(theme, "Включить подмену", state.isEnabled))
    entries.append(.enableInfo(theme, "Изменяет информацию об устройстве для серверов Telegram. Требуется перезапуск приложения."))
    
    entries.append(.profilesHeader(theme, "ВЫБЕРИТЕ УСТРОЙСТВО"))
    for profile in DeviceSpoofManager.profiles {
        let isSelected = profile.id == state.selectedProfileId
        entries.append(.profile(theme, profile.id, profile.name, isSelected))
    }
    
    // Show custom input fields only when custom profile is selected
    if state.selectedProfileId == 100 {
        entries.append(.customHeader(theme, "СВОЁ УСТРОЙСТВО"))
        entries.append(.customDeviceModel(theme, "Модель: ", state.customDeviceModel))
        entries.append(.customSystemVersion(theme, "Система: ", state.customSystemVersion))
        
        // Warning if fields are empty
        if state.customDeviceModel.isEmpty || state.customSystemVersion.isEmpty {
            entries.append(.customInfo(theme, "⚠️ Заполните оба поля. Пока поля пустые — используется реальное устройство."))
        } else {
            entries.append(.customInfo(theme, "Перезапустите приложение для применения."))
        }
    }
    
    return entries
}

// MARK: - Controller

public func deviceSpoofController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(
        DeviceSpoofControllerState(
            isEnabled: DeviceSpoofManager.shared.isEnabled,
            selectedProfileId: DeviceSpoofManager.shared.selectedProfileId,
            customDeviceModel: DeviceSpoofManager.shared.customDeviceModel,
            customSystemVersion: DeviceSpoofManager.shared.customSystemVersion
        ),
        ignoreRepeated: true
    )
    let stateValue = Atomic(value: DeviceSpoofControllerState(
        isEnabled: DeviceSpoofManager.shared.isEnabled,
        selectedProfileId: DeviceSpoofManager.shared.selectedProfileId,
        customDeviceModel: DeviceSpoofManager.shared.customDeviceModel,
        customSystemVersion: DeviceSpoofManager.shared.customSystemVersion
    ))
    
    let updateState: ((inout DeviceSpoofControllerState) -> Void) -> Void = { f in
        let result = stateValue.modify { state in
            var state = state
            f(&state)
            return state
        }
        statePromise.set(result)
    }
    
    let arguments = DeviceSpoofControllerArguments(
        toggleEnabled: { value in
            DeviceSpoofManager.shared.hasExplicitConfiguration = true
            DeviceSpoofManager.shared.isEnabled = value
            updateState { state in
                state.isEnabled = value
            }
        },
        selectProfile: { id in
            DeviceSpoofManager.shared.hasExplicitConfiguration = true
            DeviceSpoofManager.shared.selectedProfileId = id
            updateState { state in
                state.selectedProfileId = id
            }
        },
        updateCustomDeviceModel: { text in
            DeviceSpoofManager.shared.hasExplicitConfiguration = true
            DeviceSpoofManager.shared.customDeviceModel = text
            updateState { state in
                state.customDeviceModel = text
            }
        },
        updateCustomSystemVersion: { text in
            DeviceSpoofManager.shared.hasExplicitConfiguration = true
            DeviceSpoofManager.shared.customSystemVersion = text
            updateState { state in
                state.customSystemVersion = text
            }
        }
    )
    
    let signal = combineLatest(
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries = deviceSpoofControllerEntries(presentationData: presentationData, state: state)
        
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Подмена устройства"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    return controller
}
