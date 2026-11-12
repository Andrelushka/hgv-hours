import AVFoundation
import Foundation

/// Speaks alerts out loud: activity changes, limit warnings, overspeed and reminders.
/// Works while the app is open, or in the background while in-cab mode is running.
@MainActor
final class VoiceService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceService()
    private let synth = AVSpeechSynthesizer()
    private var silentWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { synth.isSpeaking }

    /// Returns once nothing is being spoken (straight away if already quiet).
    func waitUntilSilent() async {
        guard synth.isSpeaking else { return }
        await withCheckedContinuation { silentWaiters.append($0) }
        // Give the audio route a moment to settle before the microphone opens.
        try? await Task.sleep(for: .milliseconds(250))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeIfSilent() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeIfSilent() }
    }

    private func resumeIfSilent() {
        guard !synth.isSpeaking else { return }
        let waiters = silentWaiters
        silentWaiters = []
        waiters.forEach { $0.resume() }
    }
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

    /// What was said recently, so the same alert isn't repeated (e.g. by both a notification and the timer).
    private var recent: [String: Date] = [:]

    /// On daily / weekly rest with "quiet during rest" on: spoken alerts stay silent (navigation and the assistant still speak).
    var quiet = false

    func say(_ text: String, force: Bool = false) {
        guard settings.voiceEnabled || force else { return }
        guard force || !quiet else { return }
        speak(text, dedupe: true)
    }

    private func speak(_ text: String, dedupe: Bool) {
        let now = Date.now
        recent = recent.filter { now.timeIntervalSince($0.value) < 90 }
        if dedupe, recent[text] != nil { return }
        recent[text] = now
        let session = AVAudioSession.sharedInstance()
        // While the microphone session is set up, keep it: switching to playback mid-listen breaks the input.
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        }
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = Float(settings.voiceRate)
        u.voice = settings.voiceIdentifier.isEmpty
            ? (AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US"))
            : AVSpeechSynthesisVoice(identifier: settings.voiceIdentifier)
        synth.speak(u)
    }

    func stopSpeaking() { synth.stopSpeaking(at: .immediate) }

    /// Turn-by-turn prompts. `interrupt` cuts off whatever is being said so the instruction is never late.
    func sayNavigation(_ text: String, interrupt: Bool) {
        if interrupt && synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speak(text, dedupe: false)
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
