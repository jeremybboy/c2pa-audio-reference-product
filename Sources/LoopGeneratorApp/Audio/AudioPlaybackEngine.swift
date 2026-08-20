import AVFoundation
import Foundation

final class AudioPlaybackEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var sampleRate: Double = 44_100
    private var pausedPosition: Double = 0
    private(set) var duration: Double = 0
    private(set) var loopEnabled = true

    var volume: Float = 0.82 {
        didSet { player.volume = volume }
    }

    var isPlaying: Bool { player.isPlaying }
    var hasAudio: Bool { buffer != nil }

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        player.volume = volume
    }

    deinit {
        player.stop()
        engine.stop()
    }

    func load(url: URL) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        guard let loadedBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw PlaybackError.couldNotLoad
        }
        try file.read(into: loadedBuffer)
        buffer = loadedBuffer
        sampleRate = file.processingFormat.sampleRate
        duration = Double(loadedBuffer.frameLength) / sampleRate
        pausedPosition = 0
        try startEngineIfNeeded()
        scheduleFromBeginning()
    }

    func playPause() throws {
        if player.isPlaying {
            pausedPosition = currentPosition
            player.pause()
        } else {
            guard buffer != nil else { return }
            try startEngineIfNeeded()
            player.play()
        }
    }

    func restart(autoplay: Bool? = nil) throws {
        guard buffer != nil else { return }
        let shouldPlay = autoplay ?? player.isPlaying
        player.stop()
        pausedPosition = 0
        scheduleFromBeginning()
        if shouldPlay {
            try startEngineIfNeeded()
            player.play()
        }
    }

    func setLoopEnabled(_ enabled: Bool) throws {
        guard loopEnabled != enabled else { return }
        loopEnabled = enabled
        if buffer != nil {
            try restart()
        }
    }

    func stop() {
        player.stop()
        pausedPosition = 0
        buffer = nil
        duration = 0
    }

    var currentPosition: Double {
        guard duration > 0 else { return 0 }
        guard player.isPlaying,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return min(pausedPosition, duration)
        }

        let elapsed = max(0, Double(playerTime.sampleTime) / sampleRate)
        if loopEnabled {
            return elapsed.truncatingRemainder(dividingBy: duration)
        }
        return min(elapsed, duration)
    }

    private func scheduleFromBeginning() {
        guard let buffer else { return }
        let options: AVAudioPlayerNodeBufferOptions = loopEnabled ? [.loops] : []
        player.scheduleBuffer(buffer, at: nil, options: options)
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }
}

enum PlaybackError: LocalizedError {
    case couldNotLoad

    var errorDescription: String? {
        "Generated audio could not be loaded for playback."
    }
}
