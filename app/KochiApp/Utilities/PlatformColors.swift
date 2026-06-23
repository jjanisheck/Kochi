import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// System color equivalents shared by both platforms.
extension Color {
    static var systemBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    static var systemGroupedBackground: Color {
        #if os(macOS)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var systemGray4: Color { Color(red: 0.82, green: 0.82, blue: 0.84) }
    static var systemGray5: Color { Color(red: 0.90, green: 0.90, blue: 0.92) }
    static var systemGray6: Color { Color(red: 0.95, green: 0.95, blue: 0.97) }
}

/// Cross-platform navigation/text modifiers. macOS has no navigation bar, so
/// these stay no-ops there; iOS gets the real behavior.
extension View {
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(macOS)
        self
        #else
        self.navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    func hiddenNavigationBar() -> some View {
        #if os(macOS)
        self
        #else
        self.toolbar(.hidden, for: .navigationBar)
        #endif
    }

    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if os(macOS)
        self
        #else
        self.textInputAutocapitalization(.never)
        #endif
    }
}
