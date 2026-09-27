import AVFoundation
import FoGKit
import UIKit

/// Lets the caregiver hear and feel the chosen tempo on the phone while adjusting it.
@MainActor
final class MetronomePreview: ObservableObject {
    @Published private(set) var playing = false
    private var timer: Timer?
    private var beat = 0
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)
    private var player: AVAudioPlayer?

    func toggle(bpm: Int) {
        playing ? stop() : start(bpm: bpm)
    }

    func start(bpm: Int) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(data: Self.clickWAV())
        player?.prepareToPlay()
        haptic.prepare()
        playing = true
        beat = 0
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 60.0 / Double(bpm), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        playing = false
    }

    private func tick() {
        haptic.impactOccurred(intensity: beat % 4 == 0 ? 1.0 : 0.7)
        player?.currentTime = 0
        player?.play()
        beat += 1
    }

    /// 50 ms decaying 1 kHz click as an in-memory WAV, so the app ships no audio assets.
    nonisolated static func clickWAV(sampleRate: Int = 44_100) -> Data {
        let n = sampleRate / 20
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            let v = Int16(sin(2 * .pi * 1_000 * t) * exp(-t / 0.012) * 0.8 * Double(Int16.max))
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
}
