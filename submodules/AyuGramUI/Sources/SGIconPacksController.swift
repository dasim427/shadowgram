import Foundation
import UIKit
import PhotosUI
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import AppBundle

// Shadowgram: icon pack management — enabled packs in priority order, the base pack,
// installing/updating from .zip or a folder, creating a pack and drawing its icons.

private enum SGIconPacksEntry: ItemListNodeEntry {
    case header(Int32, String)
    case pack(Int32, SGIconPack, String)
    case action(Int32, String, Int)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case .header(let id, _), .pack(let id, _, _), .action(let id, _, _), .info(let id, _):
            return id / 1000
        }
    }

    var stableId: Int32 {
        switch self {
        case .header(let id, _), .pack(let id, _, _), .action(let id, _, _), .info(let id, _):
            return id
        }
    }

    static func <(lhs: SGIconPacksEntry, rhs: SGIconPacksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGIconPacksArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .pack(_, pack, label):
            return ItemListDisclosureItem(presentationData: presentationData, title: pack.metadata.name, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openPack(pack)
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

private final class SGIconPacksArguments {
    let openPack: (SGIconPack) -> Void
    let performAction: (Int) -> Void

    init(openPack: @escaping (SGIconPack) -> Void, performAction: @escaping (Int) -> Void) {
        self.openPack = openPack
        self.performAction = performAction
    }
}

private struct SGIconPacksState: Equatable {
    var packs: [SGIconPack]
    var enabled: [String]
    var base: String?

    static func current() -> SGIconPacksState {
        return SGIconPacksState(packs: sgInstalledIconPacks(), enabled: sgEnabledIconPackIds(), base: sgBaseIconPackId())
    }
}

private func sgIconPacksEntries(state: SGIconPacksState) -> [SGIconPacksEntry] {
    var entries: [SGIconPacksEntry] = []
    let packsById = Dictionary(state.packs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    entries.append(.header(0, "ВКЛЮЧЁННЫЕ НАБОРЫ"))
    var id: Int32 = 1
    for (index, packId) in state.enabled.prefix(400).enumerated() {
        if let pack = packsById[packId] {
            let base = state.base == packId ? " · базовый" : ""
            entries.append(.pack(id, pack, "\(index + 1)\(base) · \(pack.iconCount) шт."))
            id += 1
        }
    }
    if state.enabled.isEmpty {
        entries.append(.info(900, "Ни один набор не включён — везде стандартные иконки."))
    } else {
        entries.append(.info(901, "Иконка берётся из первого включённого набора, в котором она есть. Порядок меняется в меню набора."))
    }

    entries.append(.header(1000, "ВСЕ НАБОРЫ"))
    id = 1001
    for pack in state.packs.prefix(400) where !state.enabled.contains(pack.id) {
        let base = state.base == pack.id ? "базовый · " : ""
        entries.append(.pack(id, pack, "\(base)выключен · \(pack.iconCount) шт."))
        id += 1
    }
    entries.append(.info(1900, "Нажмите на набор, чтобы включить или выключить его, поменять порядок, сделать базовым, изменить иконки, поделиться или удалить. Базовый набор используется для иконок, которых нет ни в одном включённом наборе."))

    entries.append(.header(2000, "ДОБАВИТЬ"))
    entries.append(.action(2001, "Установить набор (.zip или папка)", 0))
    entries.append(.action(2002, "Новый набор иконок", 1))
    entries.append(.action(2003, "Выгрузить список имён иконок", 2))
    entries.append(.info(2004, "Набор — это .zip с metadata.json ({\"name\": \"Название\"}) и PNG-файлами, названными как иконки приложения. Если установить набор с тем же названием, он обновится. Иконки меняются после перезапуска приложения."))
    return entries
}

public func sgIconPacksController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(SGIconPacksState.current(), ignoreRepeated: true)
    let refresh: () -> Void = {
        statePromise.set(SGIconPacksState.current())
    }
    var hostControllerImpl: (() -> UIViewController?)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let showMessage: (String?, String) -> Void = { title, text in
        guard let host = hostControllerImpl?() else {
            return
        }
        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default, handler: nil))
        host.present(alert, animated: true, completion: nil)
    }

    let askName: (String, String, @escaping (String) -> Void) -> Void = { title, initial, completion in
        guard let host = hostControllerImpl?() else {
            return
        }
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = initial
            field.placeholder = "Название набора"
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Готово", style: .default, handler: { [weak alert] _ in
            let text = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                showMessage(nil, "Название не может быть пустым.")
            } else {
                completion(text)
            }
        }))
        host.present(alert, animated: true, completion: nil)
    }

    let arguments = SGIconPacksArguments(openPack: { pack in
        guard let host = hostControllerImpl?() else {
            return
        }
        let enabled = sgEnabledIconPackIds()
        let isEnabled = enabled.contains(pack.id)
        let sheet = UIAlertController(title: pack.metadata.name, message: pack.metadata.author.map { "Автор: \($0)" }, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: isEnabled ? "Выключить" : "Включить", style: .default, handler: { _ in
            sgToggleIconPack(pack.id)
            refresh()
        }))
        if isEnabled, let index = enabled.firstIndex(of: pack.id) {
            if index > 0 {
                sheet.addAction(UIAlertAction(title: "Переместить выше", style: .default, handler: { _ in
                    sgMoveIconPack(pack.id, up: true)
                    refresh()
                }))
            }
            if index + 1 < enabled.count {
                sheet.addAction(UIAlertAction(title: "Переместить ниже", style: .default, handler: { _ in
                    sgMoveIconPack(pack.id, up: false)
                    refresh()
                }))
            }
        }
        let isBase = sgBaseIconPackId() == pack.id
        sheet.addAction(UIAlertAction(title: isBase ? "Убрать из базовых" : "Сделать базовым", style: .default, handler: { _ in
            sgSetBaseIconPackId(isBase ? nil : pack.id)
            refresh()
        }))
        sheet.addAction(UIAlertAction(title: "Изменить иконки", style: .default, handler: { _ in
            pushControllerImpl?(sgIconPackIconsController(context: context, pack: pack))
        }))
        sheet.addAction(UIAlertAction(title: "Переименовать", style: .default, handler: { _ in
            askName("Название набора", pack.metadata.name, { name in
                sgRenameIconPack(pack.id, name: name)
                refresh()
            })
        }))
        sheet.addAction(UIAlertAction(title: "Поделиться (.zip)", style: .default, handler: { _ in
            guard let url = sgExportIconPack(pack), let host = hostControllerImpl?() else {
                showMessage(nil, "Не удалось упаковать набор.")
                return
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = host.view
            host.present(activity, animated: true, completion: nil)
        }))
        sheet.addAction(UIAlertAction(title: "Удалить набор", style: .destructive, handler: { _ in
            guard let host = hostControllerImpl?() else {
                return
            }
            let confirm = UIAlertController(title: "Удалить набор «\(pack.metadata.name)»?", message: nil, preferredStyle: .alert)
            confirm.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
            confirm.addAction(UIAlertAction(title: "Удалить", style: .destructive, handler: { _ in
                sgDeleteIconPack(pack.id)
                refresh()
            }))
            host.present(confirm, animated: true, completion: nil)
        }))
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = host.view
        host.present(sheet, animated: true, completion: nil)
    }, performAction: { kind in
        guard let host = hostControllerImpl?() else {
            return
        }
        switch kind {
        case 0:
            if #available(iOS 14.0, *) {
                SGIconPackPicker.present(from: host, completion: { url in
                    guard let url else {
                        return
                    }
                    switch sgImportIconPack(from: url) {
                    case let .success(name, isUpdate):
                        showMessage(isUpdate ? "Набор обновлён" : "Набор установлен", "«\(name)». Перезапусти приложение, чтобы иконки поменялись.")
                    case let .failure(text):
                        showMessage("Не удалось установить набор", text)
                    }
                    refresh()
                })
            }
        case 1:
            askName("Новый набор иконок", "Мой набор", { name in
                let id = sgCreateIconPack(name: name)
                refresh()
                if let pack = sgInstalledIconPacks().first(where: { $0.id == id }) {
                    pushControllerImpl?(sgIconPackIconsController(context: context, pack: pack))
                }
            })
        default:
            sgShareIconNameList(from: host)
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Наборы иконок"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: sgIconPacksEntries(state: state), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.didAppear = { _ in
        refresh()
    }
    hostControllerImpl = { [weak controller] in
        return controller
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}

// MARK: - Icons of one pack

private enum SGPackIconsEntry: ItemListNodeEntry {
    case header(Int32, String)
    case icon(Int32, String, Bool)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case .header(let id, _), .icon(let id, _, _), .info(let id, _):
            return id < 100000 ? 0 : 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .header(let id, _), .icon(let id, _, _), .info(let id, _):
            return id
        }
    }

    static func <(lhs: SGPackIconsEntry, rhs: SGPackIconsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGPackIconsArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .icon(_, name, isReplaced):
            let image = arguments.image(name)
            return ItemListDisclosureItem(presentationData: presentationData, icon: image, title: name, label: isReplaced ? "заменена" : "", sectionId: self.section, style: .blocks, action: {
                arguments.openIcon(name)
            })
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private final class SGPackIconsArguments {
    let image: (String) -> UIImage?
    let openIcon: (String) -> Void

    init(image: @escaping (String) -> UIImage?, openIcon: @escaping (String) -> Void) {
        self.image = image
        self.openIcon = openIcon
    }
}

private struct SGPackIconsState: Equatable {
    var names: [String]
    var replaced: Set<String>
    var revision: Int
}

func sgIconPackIconsController(context: AccountContext, pack: SGIconPack) -> ViewController {
    let names = sgKnownIconNames()
    let replacedNow: () -> Set<String> = {
        return Set(names.filter { sgIconPackImage(packId: pack.id, iconName: $0) != nil })
    }
    var revision = 0
    let statePromise = ValuePromise(SGPackIconsState(names: names, replaced: replacedNow(), revision: 0), ignoreRepeated: true)
    let refresh: () -> Void = {
        revision += 1
        statePromise.set(SGPackIconsState(names: names, replaced: replacedNow(), revision: revision))
    }
    var hostControllerImpl: (() -> UIViewController?)?

    let arguments = SGPackIconsArguments(image: { name in
        let image = sgIconPackImage(packId: pack.id, iconName: name) ?? sgOriginalBundleImage(name)
        guard let image else {
            return nil
        }
        let side: CGFloat = 29.0
        let scale = min(side / max(1.0, image.size.width), side / max(1.0, image.size.height), 1.0)
        let size = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: CGPoint(), size: size))
        }
    }, openIcon: { name in
        guard let host = hostControllerImpl?() else {
            return
        }
        let sheet = UIAlertController(title: name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Заменить картинкой из галереи", style: .default, handler: { _ in
            guard #available(iOS 14.0, *), let host = hostControllerImpl?() else {
                return
            }
            SGImagePicker.present(from: host, completion: { image in
                guard let image else {
                    return
                }
                if !sgSetIconPackImage(packId: pack.id, iconName: name, image: image) {
                    let alert = UIAlertController(title: nil, message: "Не удалось сохранить иконку.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "ОК", style: .default, handler: nil))
                    host.present(alert, animated: true, completion: nil)
                }
                refresh()
            })
        }))
        if sgIconPackImage(packId: pack.id, iconName: name) != nil {
            sheet.addAction(UIAlertAction(title: "Вернуть стандартную", style: .destructive, handler: { _ in
                sgRemoveIconPackImage(packId: pack.id, iconName: name)
                refresh()
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = host.view
        host.present(sheet, animated: true, completion: nil)
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [SGPackIconsEntry] = []
        entries.append(.header(0, "ИКОНКИ НАБОРА · ЗАМЕНЕНО \(state.replaced.count) ИЗ \(state.names.count)"))
        entries.append(.info(1, "Нажми на иконку, чтобы заменить её картинкой или вернуть стандартную. В списке иконки, которые приложение уже показывало с момента запуска, — пролистай нужные экраны, чтобы их стало больше. Изменения видны после перезапуска."))
        var id: Int32 = 100000
        for name in state.names.prefix(1500) {
            entries.append(.icon(id, name, state.replaced.contains(name)))
            id += 1
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(pack.metadata.name), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    hostControllerImpl = { [weak controller] in
        return controller
    }
    return controller
}

/// Picks one picture from the photo library as a UIImage.
@available(iOS 14.0, *)
final class SGImagePicker: NSObject, PHPickerViewControllerDelegate {
    private static var current: SGImagePicker?

    private let completion: (UIImage?) -> Void

    private init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    static func present(from controller: UIViewController, completion: @escaping (UIImage?) -> Void) {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        let handler = SGImagePicker(completion: completion)
        SGImagePicker.current = handler
        picker.delegate = handler
        controller.present(picker, animated: true, completion: nil)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        let completion = self.completion
        SGImagePicker.current = nil
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            completion(nil)
            return
        }
        provider.loadObject(ofClass: UIImage.self) { object, _ in
            let image = object as? UIImage
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}
