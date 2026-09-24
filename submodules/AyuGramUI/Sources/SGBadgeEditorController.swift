import Foundation
import UIKit
import PhotosUI

// Shadowgram: the badge editor. The canvas shows the badge rendered live; gestures on it
// move, scale and rotate the selected layer, and the controls below fine-tune it.
final class SGBadgeEditorController: UIViewController, UIGestureRecognizerDelegate {
    private var badge: SGBadge
    private let completion: (SGBadge?) -> Void
    private var selectedLayerIndex: Int?

    private let canvasContainer = UIView()
    private let canvasView = UIImageView()
    private let selectionView = UIView()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let nameField = UITextField()
    private let layerControl = UISegmentedControl()
    private let scaleSlider = UISlider()
    private let rotationSlider = UISlider()
    private let opacitySlider = UISlider()
    private let textColorButton = UIButton(type: .system)
    private let editTextButton = UIButton(type: .system)
    private let backgroundControl = UISegmentedControl(items: ["Нет", "Цвет"])
    private let backgroundColorButton = UIButton(type: .system)
    private let aspectControl = UISegmentedControl(items: ["1:1", "2:1", "3:1"])
    private let cornerSlider = UISlider()
    private var layerControls: [UIView] = []

    private var gestureStartLayer: SGBadgeLayer?

    init(badge: SGBadge, completion: @escaping (SGBadge?) -> Void) {
        self.badge = badge
        self.completion = completion
        self.selectedLayerIndex = badge.layers.isEmpty ? nil : badge.layers.count - 1
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Редактор бейджа"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Отмена", style: .plain, target: self, action: #selector(self.cancelPressed))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(self.savePressed))

        self.canvasContainer.backgroundColor = UIColor(white: 0.5, alpha: 0.15)
        self.canvasContainer.layer.cornerRadius = 12.0
        self.canvasContainer.clipsToBounds = true
        self.view.addSubview(self.canvasContainer)

        self.canvasView.contentMode = .scaleAspectFit
        self.canvasView.isUserInteractionEnabled = true
        self.canvasContainer.addSubview(self.canvasView)

        self.selectionView.isUserInteractionEnabled = false
        self.selectionView.layer.borderColor = UIColor.systemBlue.cgColor
        self.selectionView.layer.borderWidth = 1.5
        self.selectionView.layer.cornerRadius = 4.0
        self.canvasView.addSubview(self.selectionView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(self.handlePinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(self.handleRotation(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(_:)))
        for recognizer in [pan, pinch, rotation] as [UIGestureRecognizer] {
            recognizer.delegate = self
            self.canvasView.addGestureRecognizer(recognizer)
        }
        self.canvasView.addGestureRecognizer(tap)

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.keyboardDismissMode = .interactive
        self.view.addSubview(self.scrollView)

        self.stackView.axis = .vertical
        self.stackView.spacing = 10.0
        self.scrollView.addSubview(self.stackView)

        self.buildControls()
        self.reloadLayerControl()
        self.syncControls()
        self.redraw()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let safe = self.view.safeAreaInsets
        let width = self.view.bounds.width
        let canvasHeight: CGFloat = min(180.0, (width - 32.0) / CGFloat(max(1.0, self.badge.aspect)) + 40.0)
        self.canvasContainer.frame = CGRect(x: 16.0, y: safe.top + 12.0, width: width - 32.0, height: canvasHeight)
        let canvasSize = self.canvasDisplaySize()
        self.canvasView.frame = CGRect(x: floor((self.canvasContainer.bounds.width - canvasSize.width) / 2.0), y: floor((self.canvasContainer.bounds.height - canvasSize.height) / 2.0), width: canvasSize.width, height: canvasSize.height)

        let scrollTop = self.canvasContainer.frame.maxY + 8.0
        self.scrollView.frame = CGRect(x: 0.0, y: scrollTop, width: width, height: self.view.bounds.height - scrollTop)
        let stackSize = self.stackView.systemLayoutSizeFitting(CGSize(width: width - 32.0, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        self.stackView.frame = CGRect(x: 16.0, y: 8.0, width: width - 32.0, height: stackSize.height)
        self.scrollView.contentSize = CGSize(width: width, height: stackSize.height + 16.0 + safe.bottom)
        self.updateSelectionFrame()
    }

    // MARK: - Controls

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }

    private func row(_ title: String, _ control: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 15.0)
        label.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.spacing = 12.0
        row.alignment = .center
        return row
    }

    private func button(_ title: String, _ action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func buildControls() {
        let hint = UILabel()
        hint.text = "Двигай выбранный слой пальцем, разводи двумя пальцами для размера и крути для поворота. Касание выбирает слой под пальцем."
        hint.font = UIFont.systemFont(ofSize: 13.0)
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0
        self.stackView.addArrangedSubview(hint)

        self.nameField.placeholder = "Название бейджа"
        self.nameField.borderStyle = .roundedRect
        self.nameField.text = self.badge.name
        self.nameField.addTarget(self, action: #selector(self.nameChanged), for: .editingChanged)
        self.stackView.addArrangedSubview(self.nameField)

        self.stackView.addArrangedSubview(self.sectionLabel("СЛОИ"))
        self.layerControl.addTarget(self, action: #selector(self.layerSelected), for: .valueChanged)
        self.stackView.addArrangedSubview(self.layerControl)

        let addRow = UIStackView(arrangedSubviews: [
            self.button("+ Картинка", #selector(self.addImagePressed)),
            self.button("+ Текст", #selector(self.addTextPressed)),
            self.button("Центр", #selector(self.centerPressed)),
            self.button("Удалить", #selector(self.deleteLayerPressed))
        ])
        addRow.axis = .horizontal
        addRow.distribution = .fillEqually
        self.stackView.addArrangedSubview(addRow)

        let orderRow = UIStackView(arrangedSubviews: [
            self.button("Ниже", #selector(self.moveDownPressed)),
            self.button("Выше", #selector(self.moveUpPressed)),
            self.button("Дублировать", #selector(self.duplicatePressed))
        ])
        orderRow.axis = .horizontal
        orderRow.distribution = .fillEqually
        self.stackView.addArrangedSubview(orderRow)

        self.scaleSlider.minimumValue = 0.1
        self.scaleSlider.maximumValue = 3.0
        self.scaleSlider.addTarget(self, action: #selector(self.scaleChanged), for: .valueChanged)
        let scaleRow = self.row("Размер", self.scaleSlider)
        self.stackView.addArrangedSubview(scaleRow)

        self.rotationSlider.minimumValue = -Float.pi
        self.rotationSlider.maximumValue = Float.pi
        self.rotationSlider.addTarget(self, action: #selector(self.rotationChanged), for: .valueChanged)
        let rotationRow = self.row("Поворот", self.rotationSlider)
        self.stackView.addArrangedSubview(rotationRow)

        self.opacitySlider.minimumValue = 0.05
        self.opacitySlider.maximumValue = 1.0
        self.opacitySlider.addTarget(self, action: #selector(self.opacityChanged), for: .valueChanged)
        let opacityRow = self.row("Прозрачность", self.opacitySlider)
        self.stackView.addArrangedSubview(opacityRow)

        self.textColorButton.setTitle("Цвет текста", for: .normal)
        self.textColorButton.addTarget(self, action: #selector(self.textColorPressed), for: .touchUpInside)
        self.editTextButton.setTitle("Изменить текст", for: .normal)
        self.editTextButton.addTarget(self, action: #selector(self.editTextPressed), for: .touchUpInside)
        let textRow = UIStackView(arrangedSubviews: [self.editTextButton, self.textColorButton, self.button("Жирный", #selector(self.boldPressed))])
        textRow.axis = .horizontal
        textRow.distribution = .fillEqually
        self.stackView.addArrangedSubview(textRow)

        self.layerControls = [scaleRow, rotationRow, opacityRow, textRow]

        self.stackView.addArrangedSubview(self.sectionLabel("ФОН И ХОЛСТ"))
        self.backgroundControl.addTarget(self, action: #selector(self.backgroundModeChanged), for: .valueChanged)
        self.backgroundColorButton.setTitle("Сменить цвет", for: .normal)
        self.backgroundColorButton.addTarget(self, action: #selector(self.backgroundColorPressed), for: .touchUpInside)
        let backgroundRow = UIStackView(arrangedSubviews: [self.backgroundControl, self.backgroundColorButton])
        backgroundRow.axis = .horizontal
        backgroundRow.spacing = 12.0
        backgroundRow.distribution = .fillEqually
        self.stackView.addArrangedSubview(backgroundRow)

        self.aspectControl.addTarget(self, action: #selector(self.aspectChanged), for: .valueChanged)
        self.stackView.addArrangedSubview(self.row("Пропорции", self.aspectControl))

        self.cornerSlider.minimumValue = 0.0
        self.cornerSlider.maximumValue = 0.5
        self.cornerSlider.addTarget(self, action: #selector(self.cornerChanged), for: .valueChanged)
        self.stackView.addArrangedSubview(self.row("Скругление", self.cornerSlider))
    }

    private func reloadLayerControl() {
        self.layerControl.removeAllSegments()
        for (index, layer) in self.badge.layers.enumerated() {
            let title: String
            switch layer.kind {
            case .image:
                title = "Картинка \(index + 1)"
            case .text:
                title = String((layer.text ?? "Текст").prefix(8))
            }
            self.layerControl.insertSegment(withTitle: title, at: index, animated: false)
        }
        if let index = self.selectedLayerIndex, index < self.badge.layers.count {
            self.layerControl.selectedSegmentIndex = index
        } else {
            self.selectedLayerIndex = nil
            self.layerControl.selectedSegmentIndex = UISegmentedControl.noSegment
        }
        self.layerControl.isHidden = self.badge.layers.isEmpty
    }

    private func syncControls() {
        let layer = self.selectedLayerIndex.map { self.badge.layers[$0] }
        for control in self.layerControls {
            control.alpha = layer == nil ? 0.35 : 1.0
            control.isUserInteractionEnabled = layer != nil
        }
        if let layer {
            self.scaleSlider.value = Float(layer.scale)
            self.rotationSlider.value = Float(layer.rotation)
            self.opacitySlider.value = Float(layer.opacity)
            let isText = layer.kind == .text
            self.textColorButton.isEnabled = isText
            self.editTextButton.isEnabled = isText
        }
        self.backgroundControl.selectedSegmentIndex = self.badge.backgroundColor >= 0 ? 1 : 0
        self.backgroundColorButton.isEnabled = self.badge.backgroundColor >= 0
        if self.badge.aspect < 1.5 {
            self.aspectControl.selectedSegmentIndex = 0
        } else if self.badge.aspect < 2.5 {
            self.aspectControl.selectedSegmentIndex = 1
        } else {
            self.aspectControl.selectedSegmentIndex = 2
        }
        self.cornerSlider.value = Float(self.badge.cornerRadius)
    }

    // MARK: - Canvas

    private func canvasDisplaySize() -> CGSize {
        let available = CGSize(width: self.canvasContainer.bounds.width - 24.0, height: self.canvasContainer.bounds.height - 24.0)
        let aspect = CGFloat(max(0.5, min(4.0, self.badge.aspect)))
        var height = available.height
        if height * aspect > available.width {
            height = available.width / aspect
        }
        return CGSize(width: max(1.0, floor(height * aspect)), height: max(1.0, floor(height)))
    }

    private func redraw() {
        let size = self.canvasDisplaySize()
        self.canvasView.image = sgRenderBadge(self.badge, height: size.height, scale: UIScreen.main.scale)
        self.updateSelectionFrame()
    }

    private func updateSelectionFrame() {
        guard let index = self.selectedLayerIndex, index < self.badge.layers.count else {
            self.selectionView.isHidden = true
            return
        }
        let layer = self.badge.layers[index]
        let canvasSize = self.canvasView.bounds.size
        let layerSize = sgBadgeLayerSize(layer, canvasHeight: canvasSize.height)
        self.selectionView.isHidden = false
        self.selectionView.transform = .identity
        self.selectionView.bounds = CGRect(origin: CGPoint(), size: CGSize(width: layerSize.width + 6.0, height: layerSize.height + 6.0))
        self.selectionView.center = CGPoint(x: CGFloat(layer.centerX) * canvasSize.width, y: CGFloat(layer.centerY) * canvasSize.height)
        self.selectionView.transform = CGAffineTransform(rotationAngle: CGFloat(layer.rotation))
    }

    private func updateSelectedLayer(_ f: (inout SGBadgeLayer) -> Void) {
        guard let index = self.selectedLayerIndex, index < self.badge.layers.count else {
            return
        }
        f(&self.badge.layers[index])
        self.redraw()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self.canvasView)
        let canvasSize = self.canvasView.bounds.size
        for index in self.badge.layers.indices.reversed() {
            let layer = self.badge.layers[index]
            let layerSize = sgBadgeLayerSize(layer, canvasHeight: canvasSize.height)
            let center = CGPoint(x: CGFloat(layer.centerX) * canvasSize.width, y: CGFloat(layer.centerY) * canvasSize.height)
            let rect = CGRect(x: center.x - layerSize.width / 2.0 - 8.0, y: center.y - layerSize.height / 2.0 - 8.0, width: layerSize.width + 16.0, height: layerSize.height + 16.0)
            if rect.contains(point) {
                self.selectedLayerIndex = index
                self.reloadLayerControl()
                self.syncControls()
                self.updateSelectionFrame()
                return
            }
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let index = self.selectedLayerIndex, index < self.badge.layers.count else {
            return
        }
        if recognizer.state == .began {
            self.gestureStartLayer = self.badge.layers[index]
        }
        guard let start = self.gestureStartLayer else {
            return
        }
        let translation = recognizer.translation(in: self.canvasView)
        let size = self.canvasView.bounds.size
        self.updateSelectedLayer { layer in
            layer.centerX = start.centerX + Double(translation.x / max(1.0, size.width))
            layer.centerY = start.centerY + Double(translation.y / max(1.0, size.height))
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let index = self.selectedLayerIndex, index < self.badge.layers.count else {
            return
        }
        if recognizer.state == .began {
            self.gestureStartLayer = self.badge.layers[index]
        }
        guard let start = self.gestureStartLayer else {
            return
        }
        let scale = recognizer.scale
        self.updateSelectedLayer { layer in
            layer.scale = max(0.1, min(3.0, start.scale * Double(scale)))
        }
        self.syncControls()
    }

    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
        guard let index = self.selectedLayerIndex, index < self.badge.layers.count else {
            return
        }
        if recognizer.state == .began {
            self.gestureStartLayer = self.badge.layers[index]
        }
        guard let start = self.gestureStartLayer else {
            return
        }
        let rotation = recognizer.rotation
        self.updateSelectedLayer { layer in
            var value = start.rotation + Double(rotation)
            while value > Double.pi {
                value -= 2.0 * Double.pi
            }
            while value < -Double.pi {
                value += 2.0 * Double.pi
            }
            layer.rotation = value
        }
        self.syncControls()
    }

    // MARK: - Actions

    @objc private func cancelPressed() {
        self.completion(nil)
        self.dismiss(animated: true, completion: nil)
    }

    @objc private func savePressed() {
        if self.badge.name.trimmingCharacters(in: .whitespaces).isEmpty {
            self.badge.name = "Мой бейдж"
        }
        self.completion(self.badge)
        self.dismiss(animated: true, completion: nil)
    }

    @objc private func nameChanged() {
        self.badge.name = self.nameField.text ?? ""
    }

    @objc private func layerSelected() {
        let index = self.layerControl.selectedSegmentIndex
        self.selectedLayerIndex = index == UISegmentedControl.noSegment ? nil : index
        self.syncControls()
        self.updateSelectionFrame()
    }

    private func appendLayer(_ layer: SGBadgeLayer) {
        if self.badge.layers.count >= 12 {
            self.showMessage("В бейдже может быть не больше 12 слоёв. Удали лишний, чтобы добавить новый.")
            return
        }
        self.badge.layers.append(layer)
        self.selectedLayerIndex = self.badge.layers.count - 1
        self.reloadLayerControl()
        self.syncControls()
        self.redraw()
    }

    func addImageLayer(data: Data) {
        self.appendLayer(.image(data))
    }

    @objc private func addImagePressed() {
        guard #available(iOS 14.0, *) else {
            return
        }
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        self.present(picker, animated: true, completion: nil)
    }

    @objc private func addTextPressed() {
        self.askText(title: "Текст бейджа", initial: "") { [weak self] text in
            self?.appendLayer(.text(text))
        }
    }

    @objc private func editTextPressed() {
        guard let index = self.selectedLayerIndex, self.badge.layers[index].kind == .text else {
            return
        }
        self.askText(title: "Изменить текст", initial: self.badge.layers[index].text ?? "") { [weak self] text in
            self?.updateSelectedLayer { layer in
                layer.text = text
            }
            self?.reloadLayerControl()
        }
    }

    @objc private func textColorPressed() {
        self.updateSelectedLayer { layer in
            let current = sgBadgeColorPalette.firstIndex(of: layer.textColor) ?? -1
            layer.textColor = sgBadgeColorPalette[(current + 1) % sgBadgeColorPalette.count]
        }
    }

    @objc private func boldPressed() {
        self.updateSelectedLayer { layer in
            layer.isBold = !layer.isBold
        }
    }

    @objc private func centerPressed() {
        self.updateSelectedLayer { layer in
            layer.centerX = 0.5
            layer.centerY = 0.5
            layer.rotation = 0.0
        }
        self.syncControls()
    }

    @objc private func deleteLayerPressed() {
        guard let index = self.selectedLayerIndex, index < self.badge.layers.count else {
            return
        }
        self.badge.layers.remove(at: index)
        self.selectedLayerIndex = self.badge.layers.isEmpty ? nil : min(index, self.badge.layers.count - 1)
        self.reloadLayerControl()
        self.syncControls()
        self.redraw()
    }

    @objc private func moveUpPressed() {
        guard let index = self.selectedLayerIndex, index + 1 < self.badge.layers.count else {
            return
        }
        self.badge.layers.swapAt(index, index + 1)
        self.selectedLayerIndex = index + 1
        self.reloadLayerControl()
        self.redraw()
    }

    @objc private func moveDownPressed() {
        guard let index = self.selectedLayerIndex, index > 0 else {
            return
        }
        self.badge.layers.swapAt(index, index - 1)
        self.selectedLayerIndex = index - 1
        self.reloadLayerControl()
        self.redraw()
    }

    @objc private func duplicatePressed() {
        guard let index = self.selectedLayerIndex, index < self.badge.layers.count else {
            return
        }
        var copy = self.badge.layers[index]
        copy.id = UUID().uuidString
        copy.centerX += 0.05
        copy.centerY += 0.05
        self.appendLayer(copy)
    }

    @objc private func scaleChanged() {
        let value = Double(self.scaleSlider.value)
        self.updateSelectedLayer { layer in
            layer.scale = value
        }
    }

    @objc private func rotationChanged() {
        let value = Double(self.rotationSlider.value)
        self.updateSelectedLayer { layer in
            layer.rotation = value
        }
    }

    @objc private func opacityChanged() {
        let value = Double(self.opacitySlider.value)
        self.updateSelectedLayer { layer in
            layer.opacity = value
        }
    }

    @objc private func backgroundModeChanged() {
        if self.backgroundControl.selectedSegmentIndex == 0 {
            self.badge.backgroundColor = -1
        } else if self.badge.backgroundColor < 0 {
            self.badge.backgroundColor = 0x7B5CFF
        }
        self.syncControls()
        self.redraw()
    }

    @objc private func backgroundColorPressed() {
        let current = sgBadgeColorPalette.firstIndex(of: self.badge.backgroundColor) ?? -1
        self.badge.backgroundColor = sgBadgeColorPalette[(current + 1) % sgBadgeColorPalette.count]
        self.redraw()
    }

    @objc private func aspectChanged() {
        switch self.aspectControl.selectedSegmentIndex {
        case 0:
            self.badge.aspect = 1.0
        case 1:
            self.badge.aspect = 2.0
        default:
            self.badge.aspect = 3.0
        }
        self.view.setNeedsLayout()
        self.view.layoutIfNeeded()
        self.redraw()
    }

    @objc private func cornerChanged() {
        self.badge.cornerRadius = Double(self.cornerSlider.value)
        self.redraw()
    }

    // MARK: - Helpers

    private func askText(title: String, initial: String, completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = initial
            field.placeholder = "Например: 👑 Босс"
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Готово", style: .default, handler: { [weak alert] _ in
            let text = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                completion(String(text.prefix(40)))
            }
        }))
        self.present(alert, animated: true, completion: nil)
    }

    private func showMessage(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}

@available(iOS 14.0, *)
extension SGBadgeEditorController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage, let data = sgBadgeImageData(image) else {
                return
            }
            DispatchQueue.main.async {
                self?.addImageLayer(data: data)
            }
        }
    }
}
