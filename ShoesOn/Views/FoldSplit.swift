import SwiftUI

/// Two screens, one either side of the unfolded iPhone Duo's fold, and the
/// primary alone everywhere else. The secondary stays mounted while folded,
/// hidden, so opening or closing the phone only moves frames and neither
/// screen loses its scroll or state.
struct FoldSplit<Primary: View, Secondary: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var geometry = PaneGeometry(width: 0, fold: nil)
    /// Told whether it shares the display, so it can hand content over.
    @ViewBuilder var primary: (_ isSplit: Bool) -> Primary
    @ViewBuilder var secondary: () -> Secondary

    var body: some View {
        let split = UnfoldedSplit.make(width: geometry.width, isRegularWidth: sizeClass == .regular, fold: geometry.fold)
        ZStack(alignment: .topLeading) {
            // Each pane is phone-width, so its screen lays out as on a phone.
            primary(split != nil)
                .environment(\.horizontalSizeClass, split == nil ? sizeClass : .compact)
                .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity)
            secondary()
                .environment(\.horizontalSizeClass, .compact)
                .frame(maxWidth: split?.secondaryWidth ?? .infinity, maxHeight: .infinity)
                .padding(.leading, split?.secondaryX ?? 0)
                .opacity(split == nil ? 0 : 1)
                .allowsHitTesting(split != nil)
                .accessibilityHidden(split == nil)
        }
        .onGeometryChange(for: PaneGeometry.self) { proxy in
            PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
        } action: { geometry = $0 }
    }
}

private struct PaneGeometry: Equatable, Sendable {
    var width: CGFloat
    var fold: ClosedRange<CGFloat>?
}
