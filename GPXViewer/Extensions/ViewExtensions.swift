import SwiftUI

extension View {
    func rotated(_ angle: Angle) -> some View {
        self.rotationEffect(angle)
    }
}