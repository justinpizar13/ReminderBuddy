import Foundation
import SwiftUI

/// User preferences for the daily "due today" morning summary, persisted locally.
@MainActor
final class SummaryPreferences: ObservableObject {

    private enum Keys {
        static let enabled = "reminderbuddy.summary.enabled"
        static let hour = "reminderbuddy.summary.hour"
        static let minute = "reminderbuddy.summary.minute"
        static let configured = "reminderbuddy.summary.configured"
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }
    @Published var hour: Int {
        didSet { defaults.set(hour, forKey: Keys.hour) }
    }
    @Published var minute: Int {
        didSet { defaults.set(minute, forKey: Keys.minute) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey: Keys.configured) {
            isEnabled = defaults.bool(forKey: Keys.enabled)
            hour = defaults.integer(forKey: Keys.hour)
            minute = defaults.integer(forKey: Keys.minute)
        } else {
            // Sensible defaults: on, 8:00 AM.
            isEnabled = true
            hour = 8
            minute = 0
            defaults.set(true, forKey: Keys.configured)
            defaults.set(true, forKey: Keys.enabled)
            defaults.set(8, forKey: Keys.hour)
            defaults.set(0, forKey: Keys.minute)
        }
    }

    /// The configured time-of-day as a `Date` (today) for binding to a DatePicker.
    var timeOfDay: Date {
        get {
            Calendar.current.date(
                bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = comps.hour ?? 8
            minute = comps.minute ?? 0
        }
    }
}
