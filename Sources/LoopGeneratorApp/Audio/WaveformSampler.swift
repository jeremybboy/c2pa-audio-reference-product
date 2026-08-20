import AVFoundation
import Foundation

enum WaveformSampler {
    static func samples(from url: URL, count: Int = 720) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            return []
        }
        try file.read(into: buffer)

        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0 else {
            return []
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        let bucketSize = max(1, frameCount / count)
        var result: [Float] = []
        result.reserveCapacity(count)

        for bucket in 0..<count {
            let start = bucket * bucketSize
            if start >= frameCount {
                result.append(0)
                continue
            }
            let end = min(frameCount, start + bucketSize)
            var peak: Float = 0
            for channel in 0..<channelCount {
                for frame in start..<end {
                    peak = max(peak, abs(channels[channel][frame]))
                }
            }
            result.append(peak)
        }

        let maximum = result.max() ?? 1
        guard maximum > 0 else { return result }
        return result.map { $0 / maximum }
    }
}
