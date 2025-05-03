import SwiftUI

extension View {
    func rotated(_ angle: Angle) -> some View {
        self.rotationEffect(angle)
    }
}

#if os(iOS)
import UIKit

extension UIView {
    func findViewController() -> UIViewController? {
        if let nextResponder = self.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = self.next as? UIView {
            return nextResponder.findViewController()
        } else {
            return nil
        }
    }
}
#endif