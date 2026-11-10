import AVFoundation
import Foundation

/// Speaks alerts out loud: activity changes, limit warnings, overspeed and reminders.
/// Works while the app is open, or in the background while in-cab mode is running.
@MainActor
final class VoiceService {
    static let shared = VoiceService()
    private let synth = AVSpeechSynthesizer()
    private var settings = AppSettings()
    /// Warnings already spoken (so each is said once).
    private var spoken: Set<String> = []
    private var timer: Timer?
    private var statusProvider: (() -> ComplianceStatus?)?

    func configure(settings: AppSettings, status: @escaping () -> ComplianceStatus?) {
        self.settings = settings
        statusProvider = status
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkWarnings() }
        }
    }

    func update(settings: AppSettings) { self.settings = settings }

    /// English voices available on this phone, best first.
    static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.language == "en-GB" ? 1 : 0) > ($1.quality.rawValue, $1.language == "en-GB" ? 1 : 0) }
    }

    func say(_ text: String, force: Bool = false) {
        guard settings.voiceEnabled || force else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = Float(settings.voiceRate)
        u.voice = settings.voiceIdentifier.isEmpty
            ? (AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US"))
            : AVSpeechSynthesisVoice(identifier: settings.voiceIdentifier)
        synth.speak(u)
    }

    func activityChanged(to text: String) {
        guard settings.speakActivityChanges else { return }
        say(text)
    }

    func overspeed(_ text: String) {
        guard settings.speakOverspeed else { return }
        say(text)
    }

    /// A limit alert notification arriving while the app is open.
    func warning(_ title: String) {
        guard settings.speakWarnings else { return }
        say(title)
    }

    func reminder(_ title: String, _ message: String) {
        guard settings.speakReminders else { return }
        say(message.isEmpty ? title : "\(title). \(message)")
    }

    /// Speaks each upcoming limit once, a set number of minutes before it.
    private func checkWarnings() {
        guard settings.voiceEnabled, settings.speakWarnings, let s = statusProvider?() else { return }
        let lead = TimeInterval(settings.voiceWarningMinutes * 60)
        for d in Deadlines.all(s, applyWorkingTime: settings.applyWorkingTime) {
            let left = d.time.timeIntervalSince(s.now)
            guard left > 0, left <= lead else { continue }
            // Only speak deadlines that are actually counting down now.
            let active: Bool
            switch d.kind {
            case .drivingBreak, .dailyDriving, .weeklyDriving: active = s.currentKind == .drive
            case .workingBreak, .weeklyWorking, .nightWork, .gbDuty: active = s.currentKind == .drive || s.currentKind == .otherWork
            case .startRest, .weeklyRest: active = true
            case .nextStart: active = false
            }
            guard active else { continue }
            let key = "\(d.kind)-\(Int(d.time.timeIntervalSince1970 / 1800))"
            guard !spoken.contains(key) else { continue }
            spoken.insert(key)
            let minutes = Int((left / 60).rounded())
            say(d.title.hasSuffix(" by")
                ? "\(d.title) \(Fmt.time(d.time)). That's in \(minutes) minutes."
                : "\(d.title) in \(minutes) minutes, at \(Fmt.time(d.time)).")
        }
        if spoken.count > 200 { spoken.removeAll() }
    }
}
