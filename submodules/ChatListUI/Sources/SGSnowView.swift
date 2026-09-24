import Foundation
import UIKit

// Shadowgram: falling snow drawn over the chat list. Purely decorative — it ignores
// touches and uses a single CAEmitterLayer, so the cost is a few dozen sprites.
final class SGSnowView: UIView {
    private let emitterLayer = CAEmitterLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.clipsToBounds = true

        let flake = CAEmitterCell()
        flake.contents = sgSnowflakeImage().cgImage
        flake.birthRate = 5.0
        flake.lifetime = 16.0
        flake.velocity = 28.0
        flake.velocityRange = 14.0
        flake.yAcceleration = 6.0
        flake.xAcceleration = 1.5
        flake.emissionLongitude = .pi / 2.0
        flake.emissionRange = .pi / 6.0
        flake.spinRange = 1.0
        flake.scale = 0.5
        flake.scaleRange = 0.35
        flake.alphaRange = 0.3

        self.emitterLayer.emitterShape = .line
        self.emitterLayer.emitterMode = .outline
        self.emitterLayer.emitterCells = [flake]
        self.layer.addSublayer(self.emitterLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.emitterLayer.frame = self.bounds
        self.emitterLayer.emitterPosition = CGPoint(x: self.bounds.midX, y: -8.0)
        self.emitterLayer.emitterSize = CGSize(width: self.bounds.width * 1.2, height: 1.0)
    }
}

private func sgSnowflakeImage() -> UIImage {
    let size = CGSize(width: 14.0, height: 14.0)
    return UIGraphicsImageRenderer(size: size).image { context in
        let rect = CGRect(origin: .zero, size: size)
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.35, 1.0]) {
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0.0, endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width / 2.0, options: [])
        }
    }
}
