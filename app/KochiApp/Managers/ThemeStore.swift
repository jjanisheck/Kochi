//  ThemeStore.swift
//  KochiApp
//
//  Discovers theme folders bundled under Themes/, persists the selection, and
//  drives live switching. KColor reads `shared.palette`.

import SwiftUI
import Combine

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var available: [Theme]
    @Published private(set) var current: Theme
    @Published private(set) var themeVersion: Int = 0

    private let defaultsKey = "selectedThemeID"

    var palette: ThemePalette { current.palette }

    init() {
        let base = Bundle.main.url(forResource: "Themes", withExtension: nil)
        let found = ThemeStore.discover(in: base)
        self.available = found
        let storedID = UserDefaults.standard.string(forKey: defaultsKey) ?? "default"
        self.current = found.first(where: { $0.id == storedID })
            ?? found.first(where: { $0.id == "default" })
            ?? found.first
            ?? .fallbackDefault
        ActivePalette.current = current.palette
    }

    /// Scan `baseURL` for subfolders that load as valid themes. `default` first,
    /// the rest alphabetical by displayName.
    static func discover(in baseURL: URL?) -> [Theme] {
        guard let baseURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: baseURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return [.fallbackDefault]
        }
        var themes: [Theme] = []
        for url in entries {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            guard isDir.boolValue, let t = Theme.load(folderURL: url) else { continue }
            themes.append(t)
        }
        if themes.isEmpty { return [.fallbackDefault] }
        return themes.sorted { a, b in
            if a.id == "default" { return true }
            if b.id == "default" { return false }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    /// Switch themes. Bumps `themeVersion` so the root view rebuilds and KColor
    /// re-reads the new palette.
    func select(_ id: String) {
        guard id != current.id, let theme = available.first(where: { $0.id == id }) else { return }
        current = theme
        ActivePalette.current = theme.palette
        UserDefaults.standard.set(id, forKey: defaultsKey)
        themeVersion &+= 1
    }
}
