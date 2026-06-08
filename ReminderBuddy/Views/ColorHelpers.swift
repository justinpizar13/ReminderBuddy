import SwiftUI

extension Color {
    /// Creates a Color from a "#RRGGBB" hex string. Falls back to blue if malformed.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            self = .blue
            return
        }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

/// Preset palette offered when creating a category.
enum CategoryPalette {
    static let colors: [String] = [
        "#4F8EF7", // blue
        "#34C759", // green
        "#FF9500", // orange
        "#FF2D55", // pink/red
        "#AF52DE", // purple
        "#5AC8FA", // teal
        "#FFCC00", // yellow
        "#8E8E93"  // gray
    ]
}
