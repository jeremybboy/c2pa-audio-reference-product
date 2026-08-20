import AVFoundation
import AudioToolbox
import Foundation

public struct AVFoundationWAVEncoder: AudioExportEncoding {
    public init() {}

    public func encodeWAV(source: URL, destination: URL) throws {
        let sourceFile = try AVAudioFile(forReading: source)
        let sourceFormat = sourceFile.processingFormat
        guard abs(sourceFormat.sampleRate - 44_100) < 0.5,
              sourceFormat.channelCount == 2 else {
            throw ExportError.invalidSourceFormat
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let destinationFile = try AVAudioFile(
            forWriting: destination,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: 16_384
        ) else {
            throw ExportError.wavExportFailed
        }

        while sourceFile.framePosition < sourceFile.length {
            let remaining = AVAudioFrameCount(sourceFile.length - sourceFile.framePosition)
            try sourceFile.read(into: buffer, frameCount: min(buffer.frameCapacity, remaining))
            if buffer.frameLength == 0 { break }
            try destinationFile.write(from: buffer)
        }
    }
}
