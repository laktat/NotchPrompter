import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private static let fileName = "settings.json"

    var settings: PrompterSettings {
        didSet {
            guard settings != oldValue else { return }
            saver.schedule { [settings] in Persistence.save(settings, to: Self.fileName) }
        }
    }

    @ObservationIgnored private let saver = Debouncer(delay: 0.4)

    init() {
        settings = Persistence.load(PrompterSettings.self, from: Self.fileName) ?? PrompterSettings()
    }

    func adjustSpeed(by delta: Double) {
        let range = PrompterSettings.wpmRange
        settings.wordsPerMinute = min(max(settings.wordsPerMinute + delta, range.lowerBound), range.upperBound)
    }

    func flush() { saver.flush() }
}
