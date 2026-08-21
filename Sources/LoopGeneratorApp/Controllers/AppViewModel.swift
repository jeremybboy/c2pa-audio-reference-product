import AppKit
import Combine
import Foundation
import LoopGeneratorCore
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    enum AppStatus: String {
        case ready = "Ready"
        case loadingModel = "Loading Model"
        case generating = "Generating"
        case readyToPlay = "Ready to Play"
        case exporting = "Exporting"
        case error = "Error"

        var isBusy: Bool {
            self == .loadingModel || self == .generating || self == .exporting
        }
    }

    @Published var instrument: InstrumentCategory = .synth
    @Published var prompt = "Warm analog pad, evolving, cinematic, uplifting"
    @Published var duration: GenerationDuration = .eight
    @Published var seedText = ""
    @Published var loopEnabled = true
    @Published var volume = 0.82
    @Published private(set) var waveformSamples: [Float] = []
    @Published private(set) var playbackPosition = 0.0
    @Published private(set) var playbackDuration = 0.0
    @Published private(set) var isPlaying = false
    @Published private(set) var status: AppStatus = .ready
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRecord: GenerationRecord?
    @Published private(set) var modelIsAvailable = false
    @Published private(set) var c2paIsAvailable = false

    let applicationVersion: String
    private let playbackEngine = AudioPlaybackEngine()
    private let generationController: GenerationController?
    private let exportService: ExportService
    private let c2paExportService: ExportService?
    private var playbackTimer: Timer?

    init() {
        applicationVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.2.0"
        let recordStore = JSONGenerationRecordStore()
        if let adapter = try? StableAudioAdapter() {
            generationController = GenerationController(
                modelAdapter: adapter,
                recordStore: recordStore
            )
            modelIsAvailable = true
        } else {
            generationController = nil
            modelIsAvailable = false
        }
        exportService = ExportService(
            encoder: AVFoundationWAVEncoder(),
            provenanceService: NullProvenanceService()
        )
        if let provenanceService = try? C2PAProvenanceService(
            applicationVersion: applicationVersion
        ) {
            c2paExportService = ExportService(
                encoder: AVFoundationWAVEncoder(),
                provenanceService: provenanceService
            )
            c2paIsAvailable = true
        } else {
            c2paExportService = nil
            c2paIsAvailable = false
        }
        playbackEngine.volume = Float(volume)
        startPlaybackTimer()
    }

    deinit {
        playbackTimer?.invalidate()
    }

    var canGenerate: Bool {
        modelIsAvailable && !status.isBusy && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canPlay: Bool { lastRecord != nil && !status.isBusy }
    var canExport: Bool { lastRecord != nil && !status.isBusy }
    var canExportC2PA: Bool { canExport && c2paExportService != nil }

    var displayedSeed: String {
        lastRecord.map { String($0.seed) } ?? "Random"
    }

    func enforcePromptLimit() {
        if prompt.count > 200 {
            prompt = String(prompt.prefix(200))
        }
    }

    func randomizeSeed() {
        seedText = String(Int64.random(in: 0...Int64.max))
    }

    func generate() {
        guard let generationController else {
            showError(GenerationError.modelUnavailable.localizedDescription)
            return
        }

        let seed: Int64?
        let trimmedSeed = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSeed.isEmpty {
            seed = nil
        } else if let parsed = Int64(trimmedSeed), parsed >= 0 {
            seed = parsed
        } else {
            showError(GenerationError.invalidSeed.localizedDescription)
            return
        }

        status = .loadingModel
        errorMessage = nil
        playbackEngine.stop()
        isPlaying = false
        waveformSamples = []
        playbackPosition = 0
        playbackDuration = 0

        Task {
            do {
                status = .generating
                let outcome = try await generationController.generate(
                    instrument: instrument,
                    userPrompt: prompt,
                    duration: duration,
                    seed: seed
                )
                try playbackEngine.load(url: outcome.audio.audioURL)
                waveformSamples = try WaveformSampler.samples(from: outcome.audio.audioURL)
                playbackDuration = outcome.audio.durationSeconds
                lastRecord = outcome.record
                seedText = String(outcome.record.seed)
                try playbackEngine.setLoopEnabled(loopEnabled)
                playbackEngine.volume = Float(volume)
                status = .readyToPlay
            } catch let error as GenerationError {
                showError(error.localizedDescription)
            } catch {
                showError(GenerationError.generationFailed.localizedDescription)
            }
        }
    }

    func playPause() {
        do {
            try playbackEngine.playPause()
            isPlaying = playbackEngine.isPlaying
        } catch {
            showError(error.localizedDescription)
        }
    }

    func restart() {
        do {
            try playbackEngine.restart(autoplay: isPlaying)
            playbackPosition = 0
        } catch {
            showError(error.localizedDescription)
        }
    }

    func updateLoop(_ enabled: Bool) {
        loopEnabled = enabled
        do {
            try playbackEngine.setLoopEnabled(enabled)
            playbackPosition = 0
            isPlaying = playbackEngine.isPlaying
        } catch {
            showError(error.localizedDescription)
        }
    }

    func updateVolume(_ value: Double) {
        volume = value
        playbackEngine.volume = Float(value)
    }

    func exportWAV() {
        guard let record = lastRecord else { return }
        let panel = NSSavePanel()
        panel.title = "Export WAV"
        panel.nameFieldStringValue = "Loop Generator - \(record.instrument.rawValue).wav"
        panel.allowedContentTypes = [.wav]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        status = .exporting
        errorMessage = nil
        Task {
            do {
                try await exportService.exportWAV(record: record, destination: destination)
                status = .readyToPlay
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    func exportC2PAWAV() {
        guard let record = lastRecord, let c2paExportService else { return }
        let panel = NSSavePanel()
        panel.title = "Export C2PA Test WAV"
        panel.nameFieldStringValue =
            "Loop Generator - \(record.instrument.rawValue) - C2PA Test.wav"
        panel.allowedContentTypes = [.wav]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        status = .exporting
        errorMessage = nil
        Task {
            do {
                try await c2paExportService.exportWAV(
                    record: record,
                    destination: destination
                )
                status = .readyToPlay
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                playbackPosition = playbackEngine.currentPosition
                isPlaying = playbackEngine.isPlaying
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        status = .error
    }
}
