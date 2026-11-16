import AVFoundation
import UIKit
import UserNotifications

/// Mandarin text-to-speech using the voices built into iOS (works offline).
@MainActor
final class Speech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speech()

    @Published private(set) var speakingText: String?
    private let synth = AVSpeechSynthesizer()
    var rate: Float = 0.42

    override init() {
        super.init()
        synth.delegate = self
    }

    private lazy var voice: AVSpeechSynthesisVoice? = {
        let zh = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "zh-CN" }
        // prefer premium/enhanced voices when the user has downloaded one
        return zh.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }()

    var hasEnhancedVoice: Bool { (voice?.quality ?? .default) != .default }

    func speak(_ text: String, slow: Bool = false) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {}
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = slow ? max(0.2, rate * 0.62) : rate
        u.preUtteranceDelay = 0.02
        speakingText = text
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    /// Lets music that was ducked for the word come back to full volume.
    private func finished() {
        speakingText = nil
        guard !synth.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

enum Haptics {
    static var enabled = true

    static func success() { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}

/// Local daily reminders. Each of the next 14 days gets its own notification naming a word,
/// refreshed every time the app opens or closes.
enum Reminders {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// - Parameter lines: one (title, body) per upcoming day, starting today.
    static func schedule(hour: Int, minute: Int, lines: [(String, String)]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (0..<14).map { "inkstone.daily.\($0)" })
        let cal = Calendar.current
        let now = Date()
        for (i, line) in lines.prefix(14).enumerated() {
            guard let day = cal.date(byAdding: .day, value: i, to: now),
                  var fire = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            if fire <= now {
                if i == 0 { continue }
                fire = fire.addingTimeInterval(60)
            }
            let content = UNMutableNotificationContent()
            content.title = line.0
            content.body = line.1
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let req = UNNotificationRequest(identifier: "inkstone.daily.\(i)", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await center.add(req)
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: (0..<14).map { "inkstone.daily.\($0)" })
    }
}
