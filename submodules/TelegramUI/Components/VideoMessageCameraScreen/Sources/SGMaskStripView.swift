import Foundation
import UIKit
import Display
import TelegramCore

// Shadowgram: a row of mask buttons above the round video camera. Tapping one switches
// the active mask right away — also in the middle of recording.
final class SGMaskStripView: UIScrollView {
    private struct Item {
        let title: String
        let id: String?
        let preset: SGMask?
    }

    private var items: [Item] = []
    private var buttons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.showsHorizontalScrollIndicator = false
        self.showsVerticalScrollIndicator = false
        self.alwaysBounceHorizontal = true
        self.delaysContentTouches = false
        self.canCancelContentTouches = true
        // Horizontal swipes here scroll the strip instead of starting Telegram's swipe-back gesture.
        self.disablesInteractiveTransitionGestureRecognizer = true
        self.reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        for button in self.buttons {
            button.removeFromSuperview()
        }
        self.buttons.removeAll()

        let saved = SGMaskStore.load().filter { $0.id != "anonymous-calls" }
        let savedIds = Set(saved.map { $0.id })
        var items: [Item] = [Item(title: "Без маски", id: nil, preset: nil)]
        items.append(contentsOf: saved.map { Item(title: $0.name, id: $0.id, preset: nil) })
        for preset in SGMaskStore.presets() {
            let id = "strip-" + preset.id
            if !savedIds.contains(id) {
                items.append(Item(title: preset.name, id: id, preset: preset))
            }
        }
        self.items = items

        let activeId = SGMaskStore.activeId
        for (index, item) in items.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.setTitle(item.title, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
            button.setTitleColor(.white, for: .normal)
            button.contentEdgeInsets = UIEdgeInsets(top: 0.0, left: 14.0, bottom: 0.0, right: 14.0)
            button.layer.cornerRadius = 16.0
            button.clipsToBounds = true
            let isSelected = item.id == activeId
            button.backgroundColor = isSelected ? UIColor(red: 0.48, green: 0.36, blue: 1.0, alpha: 0.95) : UIColor(white: 0.0, alpha: 0.45)
            button.addTarget(self, action: #selector(self.buttonPressed(_:)), for: .touchUpInside)
            self.addSubview(button)
            self.buttons.append(button)
        }
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var x: CGFloat = 12.0
        let height: CGFloat = 32.0
        let y = floor((self.bounds.height - height) / 2.0)
        for button in self.buttons {
            let width = ceil(button.sizeThatFits(CGSize(width: 240.0, height: height)).width)
            button.frame = CGRect(x: x, y: y, width: width, height: height)
            x += width + 8.0
        }
        self.contentSize = CGSize(width: x + 4.0, height: self.bounds.height)
    }

    @objc private func buttonPressed(_ sender: UIButton) {
        guard sender.tag >= 0 && sender.tag < self.items.count else {
            return
        }
        let item = self.items[sender.tag]
        if let preset = item.preset, let id = item.id {
            var mask = preset
            mask.id = id
            SGMaskStore.save(mask)
        }
        SGMaskStore.activeId = item.id
        let offset = self.contentOffset
        self.reload()
        self.layoutIfNeeded()
        self.contentOffset = offset
    }
}
