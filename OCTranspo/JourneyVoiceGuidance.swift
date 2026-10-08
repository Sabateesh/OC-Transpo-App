import AVFAudio
import Foundation

enum JourneyVoicePrompt {
    static func text(for cue: JourneyCue, leg: JourneyLeg?) -> String? {
        switch cue.phase {
        case .leave: "\(cue.title). \(cue.detail)."
        case .walk: leg.map { "Head to \($0.board.name) for route \($0.route.name)." }
        case .wait: leg.map { "Wait at \($0.board.name) for route \($0.route.name) toward \($0.headsign)." }
        case .ride:
            if cue.count == 2 { "Two stops until \(cue.detail)." }
            else if cue.count == 1 { "Your stop is next: \(cue.detail)." }
            else { nil }
        case .getOff: "Get ready to get off at \(cue.detail)."
        case .finalWalk: "Get off and walk to \(cue.detail)."
        case .arrived: "You have arrived at \(cue.detail)."
        }
    }
    static func key(for cue: JourneyCue, legIndex: Int) -> String {
        "\(legIndex):\(cue.phase.rawValue):\(cue.phase == .ride ? cue.count ?? -1 : -1)"
    }
}

@MainActor
final class JourneyVoiceGuidance {
    private let synthesizer = AVSpeechSynthesizer()
    private var spoken: Set<String> = []
    init() { synthesizer.usesApplicationAudioSession = false }
    func reset() { synthesizer.stopSpeaking(at: .immediate); spoken = [] }
    func announce(_ cue: JourneyCue, leg: JourneyLeg?, legIndex: Int, enabled: Bool, headphonesOnly: Bool) {
        guard enabled, let words = JourneyVoicePrompt.text(for: cue, leg: leg) else { return }
        let key = JourneyVoicePrompt.key(for: cue, legIndex: legIndex)
        guard !spoken.contains(key), !headphonesOnly || Self.hasHeadphones else { return }
        spoken.insert(key)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: words)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-CA")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
    private static var hasHeadphones: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio: true
            default: false
            }
        }
    }
}
