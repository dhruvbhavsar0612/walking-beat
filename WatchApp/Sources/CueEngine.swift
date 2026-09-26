import AVFoundation
import FoGKit
import Foundation
import WatchKit

/// Turns `CueScheduler` beats into wrist haptics and sound (watch speaker or connected AirPods).
@MainActor
final class CueEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var beatIndex = 0

    private var scheduler: CueScheduler?
    private var timer: DispatchSourceTimer?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let speech = AVSpeechSynthesizer()
    private var buffers: (normal: AVAudioPCMBuffer, accent: AVAudioPCMBuffer)?
    private var style: AudioStyle = .metronome

    init() {
        engine.attach(player)
    }

    func start(_ settings: CueSettings) {
        stop()
        let s = CueScheduler(settings: settings)
        scheduler = s
        style = settings.audioStyle
        prepareAudio(settings)
        beatIndex = 0
        isRunning = true
        fire(s.beat(0))

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + s.intervalSec, repeating: s.intervalSec, leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let s = self.scheduler else { return }
                self.beatIndex += 1
                self.fire(s.beat(self.beatIndex))
            }
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        player.stop()
        speech.stopSpeaking(at: .immediate)
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
    }

    /// One short preview so caregivers can hear/feel the tempo while adjusting it.
    func preview(_ settings: CueSettings, beats: Int = 8) {
        start(settings)
        DispatchQueue.main.asyncAfter(deadline: .now() + CueScheduler(settings: settings).intervalSec * Double(beats)) { [weak self] in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func fire(_ beat: BeatOutput) {
        if beat.haptic {
            WKInterfaceDevice.current().play(beat.accent ? .directionUp : .click)
        }
        if beat.audio { playSound(accent: beat.accent) }
    }

    private func prepareAudio(_ settings: CueSettings) {
        guard settings.mode != .haptic else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = Float(settings.volume)
        buffers = (Self.tone(format, style: settings.audioStyle, accent: false),
                   Self.tone(format, style: settings.audioStyle, accent: true))
        if settings.audioStyle != .voiceCount {
            try? engine.start()
            player.play()
        }
    }

    private func playSound(accent: Bool) {
        if style == .voiceCount {
            let u = AVSpeechUtterance(string: beatIndex % 2 == 0 ? "one" : "two")
            u.rate = AVSpeechUtteranceMaximumSpeechRate * 0.6
            speech.speak(u)
            return
        }
        guard let buffers, engine.isRunning else { return }
        player.scheduleBuffer(accent ? buffers.accent : buffers.normal, at: nil, options: .interrupts)
    }

    /// Short synthesized click/drum so no audio assets are needed and latency stays low.
    private static func tone(_ format: AVAudioFormat, style: AudioStyle, accent: Bool) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let duration = style == .drum ? 0.12 : 0.05
        let frames = AVAudioFrameCount(sr * duration)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let freq: Double = style == .drum ? (accent ? 110 : 90) : (accent ? 1_600 : 1_000)
        let decay: Double = style == .drum ? 0.03 : 0.012
        let data = buf.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            data[i] = Float(sin(2 * .pi * freq * t) * exp(-t / decay) * (accent ? 1.0 : 0.8))
        }
        return buf
    }
}
