import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// System color equivalents. On macOS these map to the closest `NSColor`
/// semantic color; on iOS they use the real UIKit semantic colors.
extension Color {
    static var systemBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var systemGroupedBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    static var systemGray4: Color {
        return Color(red: 0.82, green: 0.82, blue: 0.84)
    }

    static var systemGray5: Color {
        return Color(red: 0.90, green: 0.90, blue: 0.92)
    }

    static var systemGray6: Color {
        return Color(red: 0.95, green: 0.95, blue: 0.97)
    }
}

/// Cross-platform navigation modifiers. The iOS navigation-bar APIs are
/// unavailable on macOS, so these no-op there (macOS has no navigation bar).
extension View {
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func hiddenNavigationBar() -> some View {
        #if os(iOS)
        self.navigationBarHidden(true)
        #else
        self
        #endif
    }

    /// macOS: a checkbox toggle. iOS: the standard switch (there is no checkbox
    /// style there).
    @ViewBuilder
    func checkboxToggleStyle() -> some View {
        #if os(macOS)
        self.toggleStyle(.checkbox)
        #else
        self.toggleStyle(.switch)
        #endif
    }

    /// iOS: disables autocapitalization for text entry. macOS: no-op (macOS text
    /// fields do not auto-capitalize).
    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
