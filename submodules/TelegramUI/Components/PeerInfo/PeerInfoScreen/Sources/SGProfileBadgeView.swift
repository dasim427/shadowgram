import Foundation
import UIKit
import TelegramCore

// Shadowgram: the user's badge, drawn after the name icons in their own profile. The
// badge editor renders the active badge to Documents/SGBadges/active.png; this reads it
// back, re-reading only when the file changes.

final class SGProfileBadgeView: UIImageView {
}

private var sgCachedBadgeImage: UIImage?
private var sgCachedBadgeDate: Date?

func sgProfileBadgeImage() -> UIImage? {
    guard SGExtrasManager.shared.isOn(.profileBadge) else {
        return nil
    }
    let path = NSHomeDirectory() + "/Documents/SGBadges/active.png"
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path), let date = attributes[.modificationDate] as? Date else {
        return nil
    }
    if let image = sgCachedBadgeImage, sgCachedBadgeDate == date {
        return image
    }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let image = UIImage(data: data, scale: 3.0) else {
        return nil
    }
    sgCachedBadgeImage = image
    sgCachedBadgeDate = date
    return image
}
