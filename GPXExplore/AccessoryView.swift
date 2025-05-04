/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The view for the accessories.
*/

import SwiftUI

struct AccessoryView: View {
    @Environment(\.horizontalSizeClass) private var horizontal
    @State private var size: CGSize = CGSize()

    var body: some View {
        ZStack {
            Image(.a1)
                .resizable()
                .offset(x: size.width / 2 - 420, y: size.height / 2 - 400)
                .scaledToFit()
                .frame(width: 150)
                .opacity(horizontal == .compact ? 0 : 1)
            Image(.b1)
                .resizable()
                .offset(x: size.width / 2 + 250, y: size.height / 2 - 400)
                .scaledToFit()
                .frame(width: 150)
                .opacity(horizontal == .compact ? 0 : 1)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { proxySize in
            size = proxySize
        }
    }
}

#Preview {
    AccessoryView()
}
