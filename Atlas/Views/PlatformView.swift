import SwiftUI

/// Today or Everything. Kept as one entry point for the tabs and the screen-rendering tests.
struct PlatformView: View {
    @ObservedObject var store: PlatformStore
    let today: Bool
    var body: some View {
        if today { TodayView(store: store) } else { EverythingView(store: store) }
    }
}
