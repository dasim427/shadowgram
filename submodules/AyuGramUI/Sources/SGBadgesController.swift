import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext
import UniformTypeIdentifiers

// Shadowgram: the list of profile badges — pick the active one, create, edit, share,
// import from a file or a link.

private enum SGBadgesEntry: ItemListNodeEntry {
    case header(Int32, String)
    case showToggle(Int32, Bool)
    case badge(Int32, SGBadge, Bool)
    case action(Int32, String, Int)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case .header(let id, _), .showToggle(let id, _), .badge(let id, _, _), .action(let id, _, _), .info(let id, _):
            return id / 100
        }
    }

    var stableId: Int32 {
        switch self {
        case .header(let id, _), .showToggle(let id, _), .badge(let id, _, _), .action(let id, _, _), .info(let id, _):
            return id
        }
    }

    static func <(lhs: SGBadgesEntry, rhs: SGBadgesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SGBadgesArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .showToggle(_, value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Показывать бейджик", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setShown(value)
            })
        case let .badge(_, badge, isActive):
            let icon = sgRenderBadge(badge, height: 22.0, scale: UIScreen.main.scale)
            return ItemListDisclosureItem(presentationData: presentationData, icon: icon, title: badge.name, label: isActive ? "выбран" : "", sectionId: self.section, style: .blocks, action: {
                arguments.openBadge(badge)
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

private final class SGBadgesArguments {
    let setShown: (Bool) -> Void
    let openBadge: (SGBadge) -> Void
    let performAction: (Int) -> Void

    init(setShown: @escaping (Bool) -> Void, openBadge: @escaping (SGBadge) -> Void, performAction: @escaping (Int) -> Void) {
        self.setShown = setShown
        self.openBadge = openBadge
        self.performAction = performAction
    }
}

private struct SGBadgesState: Equatable {
    var isShown: Bool
    var badges: [SGBadge]
    var activeId: String?

    static func current() -> SGBadgesState {
        return SGBadgesState(isShown: SGExtrasManager.shared.isOn(.profileBadge), badges: sgLoadBadges(), activeId: sgActiveBadgeId())
    }
}

private func sgBadgesEntries(state: SGBadgesState) -> [SGBadgesEntry] {
    var entries: [SGBadgesEntry] = []
    entries.append(.header(0, "БЕЙДЖ ПРОФИЛЯ"))
    entries.append(.showToggle(1, state.isShown))
    entries.append(.info(2, "Бейдж рисуется после твоего имени в настройках и в «Моём профиле». Видно только на этом устройстве."))

    entries.append(.header(100, "МОИ БЕЙДЖИ"))
    var id: Int32 = 101
    for badge in state.badges.prefix(90) {
        entries.append(.badge(id, badge, badge.id == state.activeId))
        id += 1
    }
    if state.badges.isEmpty {
        entries.append(.info(199, "Пока нет ни одного бейджа. Создай свой или открой готовый файл."))
    }

    entries.append(.header(200, "ДОБАВИТЬ"))
    entries.append(.action(201, "Создать свой бейдж", 0))
    entries.append(.action(202, "Открыть бейдж или картинку из файлов", 1))
    entries.append(.action(203, "Скачать бейдж по ссылке", 2))
    if state.activeId != nil {
        entries.append(.action(204, "Убрать бейдж из профиля", 3))
    }
    entries.append(.info(205, "Картинка из файла или по ссылке станет новым бейджем с одним слоем — поверх можно дописать текст или добавить ещё картинок. Файл .sgbadge импортируется целиком со всеми слоями."))
    return entries
}

public func sgBadgesController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(SGBadgesState.current(), ignoreRepeated: true)
    let refresh: () -> Void = {
        statePromise.set(SGBadgesState.current())
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

    let openEditor: (SGBadge, Bool) -> Void = { badge, activateOnSave in
        guard let host = hostControllerImpl?() else {
            return
        }
        let editor = SGBadgeEditorController(badge: badge, completion: { result in
            guard let result else {
                return
            }
            if !sgSaveBadge(result) {
                showMessage("Не удалось сохранить бейдж.")
                return
            }
            if activateOnSave || sgActiveBadgeId() == nil {
                sgSetActiveBadge(result)
            }
            refresh()
        })
        let navigationController = UINavigationController(rootViewController: editor)
        navigationController.modalPresentationStyle = .fullScreen
        host.present(navigationController, animated: true, completion: nil)
    }

    let importData: (Data) -> Void = { data in
        switch sgInterpretBadgeData(data) {
        case let .badge(badge):
            sgSaveBadge(badge)
            sgSetActiveBadge(badge)
            refresh()
        case let .image(imageData):
            var badge = SGBadge.empty(name: "Новый бейдж")
            badge.backgroundColor = -1
            badge.aspect = 1.0
            badge.layers = [.image(imageData)]
            openEditor(badge, true)
        case let .failure(text):
            showMessage(text)
        }
    }

    let arguments = SGBadgesArguments(setShown: { value in
        SGExtrasManager.shared.setOn(.profileBadge, value)
        refresh()
    }, openBadge: { badge in
        guard let host = hostControllerImpl?() else {
            return
        }
        let sheet = UIAlertController(title: badge.name, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Показывать в профиле", style: .default, handler: { _ in
            sgSetActiveBadge(badge)
            refresh()
        }))
        sheet.addAction(UIAlertAction(title: "Изменить", style: .default, handler: { _ in
            openEditor(badge, false)
        }))
        sheet.addAction(UIAlertAction(title: "Поделиться бейджем", style: .default, handler: { _ in
            guard let url = sgBadgeExportURL(badge), let host = hostControllerImpl?() else {
                return
            }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = host.view
            host.present(activity, animated: true, completion: nil)
        }))
        sheet.addAction(UIAlertAction(title: "Дублировать", style: .default, handler: { _ in
            var copy = badge
            copy.id = UUID().uuidString
            copy.name = badge.name + " (копия)"
            sgSaveBadge(copy)
            refresh()
        }))
        sheet.addAction(UIAlertAction(title: "Удалить бейдж", style: .destructive, handler: { _ in
            sgDeleteBadge(badge)
            refresh()
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
            openEditor(SGBadge.empty(name: "Мой бейдж"), true)
        case 1:
            if #available(iOS 14.0, *) {
                SGDataFilePicker.present(from: host, contentTypes: [UTType.data], completion: { data in
                    if let data {
                        importData(data)
                    }
                })
            }
        case 2:
            let alert = UIAlertController(title: "Скачать бейдж по ссылке", message: "Прямая ссылка на файл .sgbadge или на картинку PNG/JPEG.", preferredStyle: .alert)
            alert.addTextField { field in
                field.placeholder = "https://"
                field.keyboardType = .URL
                field.autocapitalizationType = .none
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Скачать", style: .default, handler: { [weak alert] _ in
                let text = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
                    showMessage("Не похоже на ссылку.")
                    return
                }
                URLSession.shared.dataTask(with: url, completionHandler: { data, _, error in
                    DispatchQueue.main.async {
                        if let data, error == nil {
                            importData(data)
                        } else {
                            showMessage("Не удалось загрузить. Проверь ссылку и интернет.")
                        }
                    }
                }).resume()
            }))
            host.present(alert, animated: true, completion: nil)
        default:
            sgSetActiveBadge(nil)
            refresh()
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Бейджи"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: sgBadgesEntries(state: state), style: .blocks, animateChanges: true)
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

/// Picks one file of the given types and returns its contents.
@available(iOS 14.0, *)
final class SGDataFilePicker: NSObject, UIDocumentPickerDelegate {
    private static var current: SGDataFilePicker?

    private let completion: (Data?) -> Void

    private init(completion: @escaping (Data?) -> Void) {
        self.completion = completion
    }

    static func present(from controller: UIViewController, contentTypes: [UTType], completion: @escaping (Data?) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        let handler = SGDataFilePicker(completion: completion)
        SGDataFilePicker.current = handler
        picker.delegate = handler
        controller.present(picker, animated: true, completion: nil)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let completion = self.completion
        SGDataFilePicker.current = nil
        guard let url = urls.first else {
            completion(nil)
            return
        }
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        completion(try? Data(contentsOf: url))
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        SGDataFilePicker.current = nil
    }
}
