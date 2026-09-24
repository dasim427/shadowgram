import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import UniformTypeIdentifiers

// Shadowgram: masks for round videos — turn them on, pick the current one, start from a
// ready-made mask, build your own in the editor, share and import `.sgmask` files.

private enum SGMasksEntry: ItemListNodeEntry {
    case header(Int32, String)
    case toggle(Int32, String, Bool)
    case noMask(Int32, Bool)
    case mask(Int32, SGMask, Bool)
    case preset(Int32, SGMask)
    case action(Int32, String, Int)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case .header(let id, _), .toggle(let id, _, _), .noMask(let id, _), .mask(let id, _, _), .preset(let id, _), .action(let id, _, _), .info(let id, _):
            return id / 100
        }
    }

    var stableId: Int32 {
        switch self {
        case .header(let id, _), .toggle(let id, _, _), .noMask(let id, _), .mask(let id, _, _), .preset(let id, _), .action(let id, _, _), .info(let id, _):
            return id
        }
    }

    static func <(lhs: SGMasksEntry, rhs: SGMasksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGMasksArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setEnabled(value)
            })
        case let .noMask(_, checked):
            return ItemListCheckboxItem(presentationData: presentationData, title: "Без маски", style: .right, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.select(nil)
            })
        case let .mask(_, mask, isActive):
            let layersText = mask.layers.map { $0.kind.title }.joined(separator: ", ")
            return ItemListDisclosureItem(presentationData: presentationData, title: mask.name, label: isActive ? "выбрана" : "", additionalDetailLabel: layersText.isEmpty ? "пусто" : layersText, sectionId: self.section, style: .blocks, action: {
                arguments.openMask(mask)
            })
        case let .preset(_, mask):
            return ItemListDisclosureItem(presentationData: presentationData, title: mask.name, label: "Надеть", sectionId: self.section, style: .blocks, action: {
                arguments.addPreset(mask)
            })
        case let .action(_, title, kind):
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.performAction(kind)
            })
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class SGMasksArguments {
    let setEnabled: (Bool) -> Void
    let select: (SGMask?) -> Void
    let openMask: (SGMask) -> Void
    let addPreset: (SGMask) -> Void
    let performAction: (Int) -> Void

    init(setEnabled: @escaping (Bool) -> Void, select: @escaping (SGMask?) -> Void, openMask: @escaping (SGMask) -> Void, addPreset: @escaping (SGMask) -> Void, performAction: @escaping (Int) -> Void) {
        self.setEnabled = setEnabled
        self.select = select
        self.openMask = openMask
        self.addPreset = addPreset
        self.performAction = performAction
    }
}

private struct SGMasksState: Equatable {
    var isEnabled: Bool
    var masks: [SGMask]
    var activeId: String?

    static func current() -> SGMasksState {
        return SGMasksState(isEnabled: SGExtrasManager.shared.roundMasksEnabled, masks: SGMaskStore.load(), activeId: SGMaskStore.activeId)
    }
}

private func sgMasksEntries(state: SGMasksState) -> [SGMasksEntry] {
    var entries: [SGMasksEntry] = []
    entries.append(.header(0, "МАСКИ В КРУЖКАХ"))
    entries.append(.toggle(1, "Маски в кружках", state.isEnabled))
    entries.append(.info(2, "Маска накладывается на фронтальную камеру при записи кружка и видна в готовом видео. Всё считается на телефоне, ничего не отправляется на сервер."))

    entries.append(.header(100, "ТЕКУЩАЯ МАСКА"))
    entries.append(.noMask(101, state.activeId == nil))
    var id: Int32 = 102
    for mask in state.masks.prefix(90) {
        entries.append(.mask(id, mask, mask.id == state.activeId))
        id += 1
    }

    entries.append(.header(200, "ГОТОВЫЕ МАСКИ"))
    id = 201
    for mask in SGMaskStore.presets() {
        entries.append(.preset(id, mask))
        id += 1
    }
    entries.append(.info(299, "Готовая маска добавится в твои и сразу наденется — потом её можно поменять в редакторе."))

    entries.append(.header(300, "СВОИ МАСКИ"))
    entries.append(.action(301, "Создать свою маску", 0))
    entries.append(.action(302, "Импортировать маску из файла", 1))
    entries.append(.info(303, "Маска — это набор слоёв: эффекты лица, искажения, фильтры, замена фона и картинки. В редакторе видно результат на себе через фронтальную камеру. Маской можно поделиться файлом .sgmask."))
    return entries
}

public func sgMasksController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(SGMasksState.current(), ignoreRepeated: true)
    let refresh: () -> Void = {
        statePromise.set(SGMasksState.current())
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

    let activate: (SGMask) -> Void = { mask in
        SGMaskStore.activeId = mask.id
        SGExtrasManager.shared.roundMasksEnabled = true
    }

    let openEditor: (SGMask, Bool) -> Void = { mask, activateOnSave in
        guard let host = hostControllerImpl?() else {
            return
        }
        let editor = SGMaskEditorController(mask: mask, completion: { result in
            guard let result else {
                return
            }
            if !SGMaskStore.save(result) {
                showMessage("Не удалось сохранить маску.")
                return
            }
            if activateOnSave {
                activate(result)
            }
            refresh()
        })
        let navigationController = UINavigationController(rootViewController: editor)
        navigationController.modalPresentationStyle = .fullScreen
        host.present(navigationController, animated: true, completion: nil)
    }

    let arguments = SGMasksArguments(setEnabled: { value in
        SGExtrasManager.shared.roundMasksEnabled = value
        refresh()
    }, select: { mask in
        SGMaskStore.activeId = mask?.id
        refresh()
    }, openMask: { mask in
        guard let host = hostControllerImpl?() else {
            return
        }
        let sheet = UIAlertController(title: mask.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Надеть", style: .default, handler: { _ in
            activate(mask)
            refresh()
        }))
        sheet.addAction(UIAlertAction(title: "Изменить", style: .default, handler: { _ in
            openEditor(mask, false)
        }))
        sheet.addAction(UIAlertAction(title: "Поделиться маской файлом", style: .default, handler: { _ in
            guard let url = SGMaskStore.exportURL(mask), let host = hostControllerImpl?() else {
                return
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = host.view
            host.present(activity, animated: true, completion: nil)
        }))
        sheet.addAction(UIAlertAction(title: "Дублировать", style: .default, handler: { _ in
            var copy = mask
            copy.id = UUID().uuidString
            copy.name = mask.name + " (копия)"
            SGMaskStore.save(copy)
            refresh()
        }))
        sheet.addAction(UIAlertAction(title: "Удалить маску", style: .destructive, handler: { _ in
            SGMaskStore.delete(mask)
            refresh()
        }))
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = host.view
        host.present(sheet, animated: true, completion: nil)
    }, addPreset: { preset in
        var mask = preset
        mask.id = UUID().uuidString
        for index in mask.layers.indices {
            mask.layers[index].id = UUID().uuidString
        }
        SGMaskStore.save(mask)
        activate(mask)
        refresh()
    }, performAction: { kind in
        guard let host = hostControllerImpl?() else {
            return
        }
        switch kind {
        case 0:
            openEditor(SGMask(name: "Моя маска", layers: []), true)
        default:
            if #available(iOS 14.0, *) {
                SGDataFilePicker.present(from: host, contentTypes: [UTType.data], completion: { data in
                    guard let data else {
                        return
                    }
                    guard let mask = SGMaskStore.importMask(data: data) else {
                        showMessage("Это не файл маски Shadowgram (.sgmask).")
                        return
                    }
                    SGMaskStore.save(mask)
                    activate(mask)
                    refresh()
                })
            }
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Маски"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: sgMasksEntries(state: state), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.didAppear = { _ in
        refresh()
    }
    hostControllerImpl = { [weak controller] in
        return controller
    }
    return controller
}
