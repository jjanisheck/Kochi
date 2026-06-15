import SwiftUI
import AppKit

/// macOS equivalents for common system colors. These map to the closest
/// `NSColor` semantic color, falling back to neutral grays that match the
/// expected light-mode shades.
extension Color {
    static var systemBackground: Color {
        return Color(nsColor: .windowBackgroundColor)
    }

    static var systemGroupedBackground: Color {
        return Color(nsColor: .underPageBackgroundColor)
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
        self
    }

    @ViewBuilder
    func hiddenNavigationBar() -> some View {
        self
    }

    /// iOS uses a full-screen cover; macOS has no equivalent, so it falls back
    /// to a sheet (which suits the locked phone-shaped window).
    @ViewBuilder
    func fullScreenCoverCompat<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        self.sheet(isPresented: isPresented, content: content)
    }

    /// iOS: disables autocapitalization for text entry. macOS: no-op (macOS text
    /// fields do not auto-capitalize).
    @ViewBuilder
    func noAutocapitalization() -> some View {
        self
    }
}
