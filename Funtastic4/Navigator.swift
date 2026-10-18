//
//  Navigator.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import AVFoundation
import MapKit
import Observation
import UIKit

/// Turn-by-turn guidance on top of the route MapKit gave us: the next turn and how far it is, what to say,
/// and whether the rider has left the route.
@Observable
final class Navigator {
    struct Guidance {
        var instruction: String
        var distanceToTurn: CLLocationDistance
        var remaining: CLLocationDistance
    }

    private(set) var isActive = false
    private(set) var guidance: Guidance?
    var isMuted = false

    private let voice = VoiceGuide()
    private var progress: RouteProgress?
    private var along: CLLocationDistance = 0
    private var offRouteFixes = 0
    private var announced: (id: String, level: Int)?

    func start() {
        isActive = true
        progress = nil
        announced = nil
        offRouteFixes = 0
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stop() {
        isActive = false
        guidance = nil
        progress = nil
        voice.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Feeds one GPS fix. Returns true once the rider has clearly left the route and a new one is needed.
    func update(_ location: CLLocation, route: MKRoute?) -> Bool {
        guard isActive, let route else { return false }
        if progress?.route !== route {
            progress = RouteProgress(route)
            along = 0
            offRouteFixes = 0
        }
        guard let progress else { return false }

        let fix = progress.locate(location.coordinate, near: along)
        along = fix.along
        if let maneuver = progress.nextManeuver(after: fix.along) {
            guidance = Guidance(instruction: maneuver.instruction, distanceToTurn: maneuver.distance,
                                remaining: progress.length - fix.along)
            announce(maneuver)
        }
        // Only trust accurate fixes, so a tunnel or tall buildings can't trigger a reroute.
        if (0...Tuning.maxAccuracy).contains(location.horizontalAccuracy) {
            offRouteFixes = fix.offRoute > Tuning.offRouteDistance ? offRouteFixes + 1 : 0
        }
        return offRouteFixes >= Tuning.offRouteFixes
    }

    /// Each turn is announced twice: once when it is about 400 m away and once right before it.
    private func announce(_ maneuver: RouteProgress.Maneuver) {
        let level = maneuver.distance <= Tuning.nearAnnounce ? 2 : (maneuver.distance <= Tuning.farAnnounce ? 1 : 0)
        let done = announced?.id == maneuver.id ? announced?.level ?? 0 : 0
        guard level > done else { return }
        announced = (maneuver.id, level)
        guard !isMuted else { return }
        let rounded = (maneuver.distance / 10).rounded() * 10
        voice.speak(level == 2 ? maneuver.instruction : "\(roadDistance(rounded, width: .wide)), \(maneuver.instruction)")
    }
}

/// "300 m" or "1.2 km", in the units the phone's region uses for roads.
func roadDistance(_ meters: CLLocationDistance, width: Measurement<UnitLength>.FormatStyle.UnitWidth = .abbreviated) -> String {
    Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: width, usage: .road))
}

/// Speaks turn instructions through the audio session meant for navigation prompts, ducking any music.
/// The `audio` background mode lets it keep speaking with the screen locked.
final class VoiceGuide: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        release(synthesizer)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        release(synthesizer)
    }

    /// Hands the audio back to music or podcasts once nothing is left to say.
    private nonisolated func release(_ synthesizer: AVSpeechSynthesizer) {
        if !synthesizer.isSpeaking {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
