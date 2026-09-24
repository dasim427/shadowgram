import Foundation
import UIKit
import AVFoundation
import CoreImage
import TelegramCore
import Camera

// Shadowgram: the mask editor. The preview is the real front camera with the mask being
// edited applied, so every change is visible on the user straight away.
final class SGMaskEditorController: UIViewController {
    private var mask: SGMask
    private let completion: (SGMask?) -> Void
    private var selectedLayerIndex: Int?

    private let previewView = UIImageView()
    private let previewHint = UILabel()
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let nameField = UITextField()
    private let layerControl = UISegmentedControl()
    private let enabledSwitch = UISwitch()
    private let intensitySlider = UISlider()
    private let optionButton = UIButton(type: .system)
    private let pictureButton = UIButton(type: .system)
    private let brightnessSlider = UISlider()
    private let contrastSlider = UISlider()
    private let saturationSlider = UISlider()
    private let positionXSlider = UISlider()
    private let positionYSlider = UISlider()
    private let sizeSlider = UISlider()
    private let rotationSlider = UISlider()
    private var adjustRows: [UIView] = []
    private var overlayRows: [UIView] = []
    private var layerRows: [UIView] = []

    private let preview = SGMaskPreviewCapture()

    init(mask: SGMask, completion: @escaping (SGMask?) -> Void) {
        self.mask = mask
        self.completion = completion
        self.selectedLayerIndex = mask.layers.isEmpty ? nil : 0
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "Редактор маски"
        self.view.backgroundColor = .systemGroupedBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Отмена", style: .plain, target: self, action: #selector(self.cancelPressed))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Сохранить", style: .done, target: self, action: #selector(self.savePressed))

        self.previewView.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
        self.previewView.contentMode = .scaleAspectFill
        self.previewView.clipsToBounds = true
        self.view.addSubview(self.previewView)

        self.previewHint.text = "Включаю камеру…"
        self.previewHint.textColor = .white
        self.previewHint.font = UIFont.systemFont(ofSize: 14.0)
        self.previewHint.textAlignment = .center
        self.previewHint.numberOfLines = 0
        self.previewView.addSubview(self.previewHint)

        self.scrollView.alwaysBounceVertical = true
        self.scrollView.keyboardDismissMode = .interactive
        self.view.addSubview(self.scrollView)
        self.stackView.axis = .vertical
        self.stackView.spacing = 10.0
        self.scrollView.addSubview(self.stackView)

        self.buildControls()
        self.reloadLayerControl()
        self.syncControls()
        self.startCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = self.view.safeAreaInsets
        let width = self.view.bounds.width
        let side = min(width - 32.0, self.view.bounds.height * 0.36)
        self.previewView.frame = CGRect(x: floor((width - side) / 2.0), y: safe.top + 10.0, width: side, height: side)
        self.previewView.layer.cornerRadius = side / 2.0
        self.previewHint.frame = self.previewView.bounds.insetBy(dx: 20.0, dy: 20.0)

        let top = self.previewView.frame.maxY + 10.0
        self.scrollView.frame = CGRect(x: 0.0, y: top, width: width, height: self.view.bounds.height - top)
        let size = self.stackView.systemLayoutSizeFitting(CGSize(width: width - 32.0, height: UIView.layoutFittingCompressedSize.height), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        self.stackView.frame = CGRect(x: 16.0, y: 6.0, width: width - 32.0, height: size.height)
        self.scrollView.contentSize = CGSize(width: width, height: size.height + 12.0 + safe.bottom)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.preview.stop()
    }

    // MARK: - Camera

    private func startCamera() {
        self.preview.mask = self.mask
        self.preview.onFrame = { [weak self] image in
            self?.previewView.image = image
            self?.previewHint.isHidden = true
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.previewHint.text = "Нет доступа к камере. Разреши его в Настройках iOS."
                    }
                }
            }
        default:
            self.previewHint.text = "Нет доступа к камере. Разреши его в Настройках iOS."
        }
    }

    private func configureSession() {
        if !self.preview.start() {
            self.previewHint.text = "Камера недоступна на этом устройстве. Маска сохранится и сработает при записи кружка."
        }
    }

    private func maskChanged() {
        self.preview.mask = self.mask
    }

    // MARK: - Controls

    private func label(_ text: String, header: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = header ? UIFont.systemFont(ofSize: 13.0, weight: .semibold) : UIFont.systemFont(ofSize: 15.0)
        label.textColor = header ? .secondaryLabel : .label
        return label
    }

    private func row(_ title: String, _ control: UIView) -> UIView {
        let titleLabel = self.label(title)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [titleLabel, control])
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

    private func slider(_ slider: UISlider, min: Float, max: Float, _ action: Selector) -> UISlider {
        slider.minimumValue = min
        slider.maximumValue = max
        slider.addTarget(self, action: action, for: .valueChanged)
        return slider
    }

    private func buildControls() {
        self.nameField.placeholder = "Название маски"
        self.nameField.borderStyle = .roundedRect
        self.nameField.text = self.mask.name
        self.nameField.addTarget(self, action: #selector(self.nameChanged), for: .editingChanged)
        self.stackView.addArrangedSubview(self.nameField)

        self.stackView.addArrangedSubview(self.label("СЛОИ — СВЕРХУ ВНИЗ ПО ПОРЯДКУ ПРИМЕНЕНИЯ", header: true))
        self.layerControl.addTarget(self, action: #selector(self.layerSelected), for: .valueChanged)
        self.stackView.addArrangedSubview(self.layerControl)

        let layerButtons = UIStackView(arrangedSubviews: [
            self.button("+ Слой", #selector(self.addLayerPressed)),
            self.button("Раньше", #selector(self.moveEarlierPressed)),
            self.button("Позже", #selector(self.moveLaterPressed)),
            self.button("Удалить", #selector(self.deleteLayerPressed))
        ])
        layerButtons.axis = .horizontal
        layerButtons.distribution = .fillEqually
        self.stackView.addArrangedSubview(layerButtons)

        self.enabledSwitch.addTarget(self, action: #selector(self.enabledChanged), for: .valueChanged)
        let enabledRow = self.row("Слой включён", self.enabledSwitch)
        let intensityRow = self.row("Сила", self.slider(self.intensitySlider, min: 0.0, max: 1.0, #selector(self.intensityChanged)))
        self.optionButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.optionButton.contentHorizontalAlignment = .leading
        self.optionButton.addTarget(self, action: #selector(self.optionPressed), for: .touchUpInside)
        self.pictureButton.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.pictureButton.contentHorizontalAlignment = .leading
        self.pictureButton.addTarget(self, action: #selector(self.picturePressed), for: .touchUpInside)
        for view in [enabledRow, intensityRow, self.optionButton, self.pictureButton] as [UIView] {
            self.stackView.addArrangedSubview(view)
        }
        self.layerRows = [enabledRow, intensityRow]

        self.adjustRows = [
            self.row("Яркость", self.slider(self.brightnessSlider, min: -1.0, max: 1.0, #selector(self.adjustChanged))),
            self.row("Контраст", self.slider(self.contrastSlider, min: -1.0, max: 1.0, #selector(self.adjustChanged))),
            self.row("Насыщенность", self.slider(self.saturationSlider, min: -1.0, max: 1.0, #selector(self.adjustChanged)))
        ]
        self.overlayRows = [
            self.row("По горизонтали", self.slider(self.positionXSlider, min: 0.0, max: 1.0, #selector(self.overlayChanged))),
            self.row("По вертикали", self.slider(self.positionYSlider, min: 0.0, max: 1.0, #selector(self.overlayChanged))),
            self.row("Размер", self.slider(self.sizeSlider, min: 0.2, max: 2.5, #selector(self.overlayChanged))),
            self.row("Поворот", self.slider(self.rotationSlider, min: -Float.pi, max: Float.pi, #selector(self.overlayChanged)))
        ]
        for view in self.adjustRows + self.overlayRows {
            self.stackView.addArrangedSubview(view)
        }

        self.stackView.addArrangedSubview(self.label("Эффекты лица ищут лицо в кадре, поэтому держи его в круге. Замена и размытие фона работают на iOS 15 и новее. Маска применяется к фронтальной камере при записи кружка."))
    }

    private func reloadLayerControl() {
        self.layerControl.removeAllSegments()
        for (index, layer) in self.mask.layers.enumerated() {
            self.layerControl.insertSegment(withTitle: "\(index + 1). " + String(layer.kind.title.prefix(10)), at: index, animated: false)
        }
        if let index = self.selectedLayerIndex, index < self.mask.layers.count {
            self.layerControl.selectedSegmentIndex = index
        } else {
            self.selectedLayerIndex = self.mask.layers.isEmpty ? nil : 0
            self.layerControl.selectedSegmentIndex = self.selectedLayerIndex ?? UISegmentedControl.noSegment
        }
        self.layerControl.isHidden = self.mask.layers.isEmpty
    }

    private func syncControls() {
        let layer = self.selectedLayerIndex.map { self.mask.layers[$0] }
        for view in self.layerRows {
            view.isHidden = layer == nil
        }
        guard let layer else {
            self.optionButton.isHidden = true
            self.pictureButton.isHidden = true
            for view in self.adjustRows + self.overlayRows {
                view.isHidden = true
            }
            return
        }
        self.enabledSwitch.isOn = layer.isEnabled
        self.intensitySlider.value = Float(layer.intensity)

        switch layer.kind {
        case .colorFilter:
            self.optionButton.isHidden = false
            self.optionButton.setTitle("Фильтр: " + (SGMaskColorFilter(rawValue: layer.filter ?? "")?.title ?? "—"), for: .normal)
        case .emojiFace:
            self.optionButton.isHidden = false
            self.optionButton.setTitle("Эмодзи: " + (layer.text ?? "😎"), for: .normal)
        case .colorBackground:
            self.optionButton.isHidden = false
            self.optionButton.setTitle("Сменить цвет фона", for: .normal)
        default:
            self.optionButton.isHidden = true
        }

        switch layer.kind {
        case .swapFace:
            self.pictureButton.isHidden = false
            self.pictureButton.setTitle(layer.imageData == nil ? "Выбрать фото лица" : "Заменить фото лица", for: .normal)
        case .imageBackground, .overlayImage:
            self.pictureButton.isHidden = false
            self.pictureButton.setTitle(layer.imageData == nil ? "Выбрать картинку" : "Заменить картинку", for: .normal)
        default:
            self.pictureButton.isHidden = true
        }

        let isAdjust = layer.kind == .adjust
        for view in self.adjustRows {
            view.isHidden = !isAdjust
        }
        self.brightnessSlider.value = Float(layer.brightness)
        self.contrastSlider.value = Float(layer.contrast)
        self.saturationSlider.value = Float(layer.saturation)

        let isOverlay = layer.kind == .overlayImage
        for view in self.overlayRows {
            view.isHidden = !isOverlay
        }
        self.positionXSlider.value = Float(layer.centerX)
        self.positionYSlider.value = Float(layer.centerY)
        self.sizeSlider.value = Float(layer.scale)
        self.rotationSlider.value = Float(layer.rotation)
        self.view.setNeedsLayout()
    }

    private func updateSelectedLayer(_ f: (inout SGMaskLayer) -> Void) {
        guard let index = self.selectedLayerIndex, index < self.mask.layers.count else {
            return
        }
        f(&self.mask.layers[index])
        self.maskChanged()
    }

    // MARK: - Actions

    @objc private func cancelPressed() {
        self.completion(nil)
        self.dismiss(animated: true, completion: nil)
    }

    @objc private func savePressed() {
        if self.mask.name.trimmingCharacters(in: .whitespaces).isEmpty {
            self.mask.name = "Моя маска"
        }
        self.completion(self.mask)
        self.dismiss(animated: true, completion: nil)
    }

    @objc private func nameChanged() {
        self.mask.name = self.nameField.text ?? ""
    }

    @objc private func layerSelected() {
        let index = self.layerControl.selectedSegmentIndex
        self.selectedLayerIndex = index == UISegmentedControl.noSegment ? nil : index
        self.syncControls()
    }

    @objc private func addLayerPressed() {
        if self.mask.layers.count >= SGMask.maxLayers {
            self.showMessage("В одной маске может быть не больше \(SGMask.maxLayers) слоёв. Удали лишний, чтобы добавить новый.")
            return
        }
        let sheet = UIAlertController(title: "Новый слой", message: nil, preferredStyle: .actionSheet)
        for kind in SGMaskLayer.Kind.allCases {
            sheet.addAction(UIAlertAction(title: kind.title, style: .default, handler: { [weak self] _ in
                self?.appendLayer(SGMaskLayer(kind: kind))
            }))
        }
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.sourceView = self.view
        self.present(sheet, animated: true, completion: nil)
    }

    private func appendLayer(_ layer: SGMaskLayer) {
        self.mask.layers.append(layer)
        self.selectedLayerIndex = self.mask.layers.count - 1
        self.maskChanged()
        self.reloadLayerControl()
        self.syncControls()
        if layer.kind.needsBackgroundSeparation {
            if #available(iOS 15.0, *) {
            } else {
                self.showMessage("Отделение от фона работает только на iOS 15 и новее — на этом устройстве слой ничего не сделает.")
            }
        }
    }

    @objc private func deleteLayerPressed() {
        guard let index = self.selectedLayerIndex, index < self.mask.layers.count else {
            return
        }
        self.mask.layers.remove(at: index)
        self.selectedLayerIndex = self.mask.layers.isEmpty ? nil : min(index, self.mask.layers.count - 1)
        self.maskChanged()
        self.reloadLayerControl()
        self.syncControls()
    }

    @objc private func moveEarlierPressed() {
        guard let index = self.selectedLayerIndex, index > 0 else {
            return
        }
        self.mask.layers.swapAt(index, index - 1)
        self.selectedLayerIndex = index - 1
        self.maskChanged()
        self.reloadLayerControl()
    }

    @objc private func moveLaterPressed() {
        guard let index = self.selectedLayerIndex, index + 1 < self.mask.layers.count else {
            return
        }
        self.mask.layers.swapAt(index, index + 1)
        self.selectedLayerIndex = index + 1
        self.maskChanged()
        self.reloadLayerControl()
    }

    @objc private func enabledChanged() {
        let value = self.enabledSwitch.isOn
        self.updateSelectedLayer { layer in
            layer.isEnabled = value
        }
    }

    @objc private func intensityChanged() {
        let value = Double(self.intensitySlider.value)
        self.updateSelectedLayer { layer in
            layer.intensity = value
        }
    }

    @objc private func adjustChanged() {
        let brightness = Double(self.brightnessSlider.value)
        let contrast = Double(self.contrastSlider.value)
        let saturation = Double(self.saturationSlider.value)
        self.updateSelectedLayer { layer in
            layer.brightness = brightness
            layer.contrast = contrast
            layer.saturation = saturation
        }
    }

    @objc private func overlayChanged() {
        let x = Double(self.positionXSlider.value)
        let y = Double(self.positionYSlider.value)
        let size = Double(self.sizeSlider.value)
        let rotation = Double(self.rotationSlider.value)
        self.updateSelectedLayer { layer in
            layer.centerX = x
            layer.centerY = y
            layer.scale = size
            layer.rotation = rotation
        }
    }

    @objc private func optionPressed() {
        guard let index = self.selectedLayerIndex, index < self.mask.layers.count else {
            return
        }
        switch self.mask.layers[index].kind {
        case .colorFilter:
            let sheet = UIAlertController(title: "Фильтр", message: nil, preferredStyle: .actionSheet)
            for filter in SGMaskColorFilter.allCases {
                sheet.addAction(UIAlertAction(title: filter.title, style: .default, handler: { [weak self] _ in
                    self?.updateSelectedLayer { layer in
                        layer.filter = filter.rawValue
                    }
                    self?.syncControls()
                }))
            }
            sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
            sheet.popoverPresentationController?.sourceView = self.view
            self.present(sheet, animated: true, completion: nil)
        case .emojiFace:
            let alert = UIAlertController(title: "Эмодзи на лицо", message: "Вставь один эмодзи.", preferredStyle: .alert)
            alert.addTextField { field in
                field.text = self.mask.layers[index].text
            }
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Готово", style: .default, handler: { [weak self, weak alert] _ in
                let text = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let first = text.first else {
                    return
                }
                self?.updateSelectedLayer { layer in
                    layer.text = String(first)
                }
                self?.syncControls()
            }))
            self.present(alert, animated: true, completion: nil)
        case .colorBackground:
            let palette = [0x1C1238, 0x000000, 0xFFFFFF, 0x34C759, 0x007AFF, 0xFF2D55, 0xFFCC00, 0x7B5CFF]
            self.updateSelectedLayer { layer in
                let current = palette.firstIndex(of: layer.color) ?? -1
                layer.color = palette[(current + 1) % palette.count]
            }
        default:
            break
        }
    }

    @objc private func picturePressed() {
        guard #available(iOS 14.0, *), let index = self.selectedLayerIndex, index < self.mask.layers.count else {
            return
        }
        let kind = self.mask.layers[index].kind
        SGImagePicker.present(from: self, completion: { [weak self] image in
            guard let self, let image, let data = sgMaskImageData(image) else {
                return
            }
            if kind == .swapFace && !sgMaskPhotoHasFace(data) {
                self.showMessage("На этом фото не нашлось лица. Возьми снимок, где лицо крупно, прямо и при хорошем свете.")
                return
            }
            self.updateSelectedLayer { layer in
                layer.imageData = data
            }
            self.syncControls()
        })
    }

    private func showMessage(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "ОК", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}

/// Downscales a picked picture to at most 1024 px on the long side, as JPEG.
func sgMaskImageData(_ image: UIImage) -> Data? {
    let maxSide: CGFloat = 1024.0
    let largest = max(image.size.width, image.size.height)
    let factor = largest > maxSide ? maxSide / largest : 1.0
    let size = CGSize(width: floor(image.size.width * factor), height: floor(image.size.height * factor))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(in: CGRect(origin: CGPoint(), size: size))
    }
    return scaled.jpegData(compressionQuality: 0.85)
}

/// Runs the front camera for the mask editor and renders each frame with the mask. Kept
/// out of the view controller so the capture callbacks stay off the main actor.
final class SGMaskPreviewCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "shadowgram.mask.preview")
    private let engine = SGMaskEngine()
    private let ciContext = CIContext()
    private let lock = NSLock()
    private var currentMask = SGMask(name: "", layers: [])
    private var isRendering = false

    /// Called on the main queue with every rendered frame.
    var onFrame: ((UIImage) -> Void)?

    var mask: SGMask {
        get {
            self.lock.lock()
            defer {
                self.lock.unlock()
            }
            return self.currentMask
        }
        set {
            self.lock.lock()
            self.currentMask = newValue
            self.lock.unlock()
        }
    }

    func start() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front), let input = try? AVCaptureDeviceInput(device: device) else {
            return false
        }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: self.queue)

        self.session.beginConfiguration()
        if self.session.canSetSessionPreset(.vga640x480) {
            self.session.sessionPreset = .vga640x480
        }
        if self.session.canAddInput(input) {
            self.session.addInput(input)
        }
        if self.session.canAddOutput(output) {
            self.session.addOutput(output)
        }
        self.session.commitConfiguration()

        let session = self.session
        self.queue.async {
            session.startRunning()
        }
        return true
    }

    func stop() {
        let session = self.session
        self.queue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        self.lock.lock()
        if self.isRendering {
            self.lock.unlock()
            return
        }
        self.isRendering = true
        let mask = self.currentMask
        self.lock.unlock()

        var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.leftMirrored)
        let side = min(image.extent.width, image.extent.height)
        let crop = CGRect(x: image.extent.midX - side / 2.0, y: image.extent.midY - side / 2.0, width: side, height: side)
        image = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let processed = self.engine.apply(mask: mask, to: image)
        let cgImage = self.ciContext.createCGImage(processed, from: processed.extent)

        DispatchQueue.main.async {
            if let cgImage {
                self.onFrame?(UIImage(cgImage: cgImage))
            }
            self.lock.lock()
            self.isRendering = false
            self.lock.unlock()
        }
    }
}
