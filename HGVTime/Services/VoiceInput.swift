import AVFoundation
import Foundation
import Observation
import Speech

/// Listens to the microphone and turns speech into text. Stops by itself after a short silence.
@MainActor
@Observable
final class VoiceInput {
    var transcript = ""
    var isListening = false
    var error: String?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    @ObservationIgnored private let audio = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Timer?
    @ObservationIgnored private var onFinish: ((String) -> Void)?

    func start(onFinish: @escaping (String) -> Void) async {
        error = nil
        self.onFinish = onFinish
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else { error = "Allow microphone and speech recognition for HGV Hours in iPhone Settings."; return }
        guard let recognizer, recognizer.isAvailable else { error = "Speech recognition isn't available right now."; return }

        stopEngine()
        transcript = ""
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }
        audio.prepare()
        do { try audio.start() } catch { self.error = "Couldn't start the microphone."; return }
        isListening = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal { self.finish() }
                }
                if err != nil && self.isListening { self.finish() }
            }
        }
        resetSilenceTimer(initial: true)
    }

    /// Stop listening and hand over what was heard.
    func finish() {
        guard isListening else { return }
        let text = transcript
        stopEngine()
        let callback = onFinish
        onFinish = nil
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { callback?(text) }
    }

    func cancel() {
        onFinish = nil
        stopEngine()
    }

    private func resetSilenceTimer(initial: Bool = false) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: initial ? 6 : 1.6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }

    private func stopEngine() {
        silenceTimer?.invalidate()
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Things you can tell the assistant to do.
enum VoiceCommand: Equatable {
    case activity(DutyKind), subtype(ActivitySubtype), startShift, endShift(RestType), cardIn, cardOut, arrived

    /// Recognises simple spoken commands ("start driving", "take a break", "end shift weekly rest"…). nil if it's a question.
    static func parse(_ text: String) -> VoiceCommand? {
        let t = " " + text.lowercased().replacingOccurrences(of: "[^a-z ]", with: " ", options: .regularExpression) + " "
        func has(_ w: String...) -> Bool { w.contains { t.contains(" \($0) ") || t.contains(" \($0)") } }
        guard !has("how", "when", "what", "can i", "why", "should") else { return nil }
        if has("start shift", "start my shift", "begin shift", "start work") { return .startShift }
        if has("end shift", "end my shift", "finish shift", "finish work", "daily rest", "weekly rest") {
            return .endShift(has("weekly") ? .weekly : .daily)
        }
        if has("insert card", "card in", "inserted card", "put card in", "put my card in") { return .cardIn }
        if has("withdraw card", "card out", "remove card", "take card out", "take my card out") { return .cardOut }
        if has("arrived", "i m here", "at the delivery", "at the collection") { return .arrived }
        if has("unloading", "tipping") { return .subtype(.unloading) }
        if has("loading") { return .subtype(.loading) }
        if has("vehicle check", "walk round", "walkaround", "defect check") { return .subtype(.vehicleCheck) }
        if has("fuelling", "refuel", "fuel up") { return .subtype(.fuelling) }
        if has("yard check") { return .subtype(.yardCheck) }
        if has("spare", "standby") { return .subtype(.spare) }
        if has("waiting for shift", "wait for shift") { return .subtype(.waitingShift) }
        if has("waiting for job", "wait for job", "waiting for a job") { return .subtype(.waitingJob) }
        if has("waiting", "wait to") { return .subtype(t.contains("unload") || t.contains("tip") ? .waitingUnload : .waitingLoad) }
        if has("ferry", "train") { return .subtype(.ferryTrain) }
        if has("break", "stop for a break", "take a break") { return .activity(.rest) }
        if has("poa", "availability") { return .activity(.availability) }
        if has("other work", "working") { return .activity(.otherWork) }
        if has("drive", "driving", "start driving", "set off") { return .activity(.drive) }
        return nil
    }

    var confirmation: String {
        switch self {
        case .activity(let k): k == .rest ? "Break started." : "\(k.title) started."
        case .subtype(let s): "\(s.title) started."
        case .startShift: "Shift started."
        case .endShift(let r): "Shift ended. \(r == .weekly ? "Weekly" : "Daily") rest started."
        case .cardIn: "Driver card marked as inserted."
        case .cardOut: "Driver card marked as withdrawn."
        case .arrived: "Arrival recorded."
        }
    }
}
