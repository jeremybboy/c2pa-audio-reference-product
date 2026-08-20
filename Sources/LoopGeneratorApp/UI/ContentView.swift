import LoopGeneratorCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Color.lgBorder)
            HStack(alignment: .top, spacing: 24) {
                generatorPanel
                    .frame(width: 570)
                previewPanel
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .background(
            LinearGradient(
                colors: [Color.lgBackgroundTop, Color.lgBackground],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(minWidth: 1180, minHeight: 760)
        .preferredColorScheme(.dark)
        .background(WindowConfigurator())
    }

    private var topBar: some View {
        ZStack {
            Color.black.opacity(0.16)
            HStack(spacing: 10) {
                Spacer()
                Image(systemName: "waveform")
                    .foregroundStyle(Color.lgPurpleBright)
                Text("Loop Generator")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            HStack {
                Spacer()
                Text("v0.1.0")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.lgMuted)
                    .padding(.trailing, 20)
            }
        }
        .frame(height: 52)
    }

    private var generatorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Loop Generator")
                .font(.system(size: 31, weight: .bold, design: .rounded))
            Text("AI Instrumental Loop Generator")
                .font(.system(size: 16))
                .foregroundStyle(Color.lgSecondary)
                .padding(.top, 6)
            HStack(spacing: 4) {
                Text("Powered by")
                    .foregroundStyle(Color.lgSecondary)
                Text("Stable Audio Open Small")
                    .foregroundStyle(Color.lgPurpleBright)
            }
            .font(.system(size: 15))
            .padding(.top, 5)

            sectionLabel("1. INSTRUMENT")
                .padding(.top, 36)
            HStack(spacing: 8) {
                ForEach(InstrumentCategory.allCases, id: \.self) { instrument in
                    InstrumentButton(
                        instrument: instrument,
                        selected: viewModel.instrument == instrument
                    ) {
                        viewModel.instrument = instrument
                    }
                }
            }

            sectionLabel("2. PROMPT")
                .padding(.top, 32)
            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $viewModel.prompt)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(11)
                    .background(Color.clear)
                    .onChange(of: viewModel.prompt) {
                        viewModel.enforcePromptLimit()
                    }
                Text("\(viewModel.prompt.count) / 200")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.lgMuted)
                    .padding(12)
            }
            .frame(height: 126)
            .background(Color.lgControlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.lgBorder, lineWidth: 1)
            )

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel("3. DURATION")
                    Picker("Duration", selection: $viewModel.duration) {
                        ForEach(GenerationDuration.allCases) { duration in
                            Text(duration.label).tag(duration)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                    .controlSize(.large)
                }
                VStack(alignment: .leading, spacing: 9) {
                    sectionLabel("4. SEED (optional)")
                    HStack(spacing: 8) {
                        TextField("Random", text: $viewModel.seedText)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(Color.lgControlBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.lgBorder, lineWidth: 1)
                            )
                        Button(action: viewModel.randomizeSeed) {
                            Image(systemName: "dice")
                                .font(.system(size: 16))
                                .frame(width: 42, height: 42)
                        }
                        .buttonStyle(SecondaryIconButtonStyle())
                        .help("Generate a random seed")
                    }
                }
            }
            .padding(.top, 30)

            Button(action: viewModel.generate) {
                HStack(spacing: 10) {
                    if viewModel.status == .generating || viewModel.status == .loadingModel {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(viewModel.status == .generating ? "Generating…" : "Generate Loop")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!viewModel.canGenerate)
            .padding(.top, 30)

            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Model")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.lgMuted)
                    Text("Stable Audio Open Small")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.lgSecondary)
                }
                Spacer()
                Text(viewModel.modelIsAvailable ? "Local" : "Setup required")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(viewModel.modelIsAvailable ? Color.green : Color.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background((viewModel.modelIsAvailable ? Color.green : Color.orange).opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .padding(16)
            .background(Color.lgCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.lgBorder, lineWidth: 1))
            .padding(.top, 46)

            if let error = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.orange)
                .padding(.top, 12)
            }
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 20) {
            VStack(spacing: 0) {
                HStack {
                    Text("PREVIEW")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(previewMetadata)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.lgSecondary)
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.lgMuted)
                }
                .padding(.horizontal, 20)
                .frame(height: 58)

                WaveformView(
                    samples: viewModel.waveformSamples,
                    progress: waveformProgress
                )
                .frame(minHeight: 250)
                .padding(.horizontal, 18)

                HStack {
                    Text(formatTime(viewModel.playbackPosition))
                    Spacer()
                    Text(formatTime(viewModel.playbackDuration))
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.lgMuted)
                .padding(.horizontal, 22)
                .padding(.top, 9)
                .padding(.bottom, 16)

                Divider().overlay(Color.lgBorder)

                HStack {
                    Toggle("Loop", isOn: Binding(
                        get: { viewModel.loopEnabled },
                        set: viewModel.updateLoop
                    ))
                    .toggleStyle(.switch)
                    .tint(Color.lgPurple)

                    Spacer()
                    Button(action: viewModel.restart) {
                        Image(systemName: "backward.end.fill")
                    }
                    .buttonStyle(TransportButtonStyle())
                    .disabled(!viewModel.canPlay)

                    Button(action: viewModel.playPause) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .frame(width: 50, height: 50)
                    }
                    .buttonStyle(PlayButtonStyle())
                    .disabled(!viewModel.canPlay)
                    .padding(.horizontal, 20)

                    Button(action: viewModel.restart) {
                        Image(systemName: "forward.end.fill")
                    }
                    .buttonStyle(TransportButtonStyle())
                    .disabled(!viewModel.canPlay)
                    Spacer()

                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.lgSecondary)
                    Slider(
                        value: Binding(
                            get: { viewModel.volume },
                            set: viewModel.updateVolume
                        ),
                        in: 0...1
                    )
                    .tint(Color.lgPurpleBright)
                    .frame(width: 155)
                }
                .padding(.horizontal, 22)
                .frame(height: 90)
            }
            .background(Color.lgCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.lgBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 14) {
                Text("EXPORT")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "music.note")
                        Text("WAV (44.1 kHz, 24-bit, Stereo)")
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .foregroundStyle(Color.lgSecondary)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(Color.lgControlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.lgBorder, lineWidth: 1))

                    Button("Export WAV", action: viewModel.exportWAV)
                        .buttonStyle(ExportButtonStyle())
                        .disabled(!viewModel.canExport)
                        .frame(width: 210, height: 46)
                }

                HStack {
                    Spacer()
                    Image(systemName: "lock")
                    Text("Export with C2PA (coming next)")
                    Spacer()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.lgMuted.opacity(0.7))
                .frame(height: 42)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.lgBorder, lineWidth: 1))

                Text("Generation records are retained for the future provenance pipeline.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.lgMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(18)
            .background(Color.lgCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.lgBorder, lineWidth: 1))
        }
    }

    private var footer: some View {
        HStack(spacing: 28) {
            Text(viewModel.status.rawValue)
                .foregroundStyle(viewModel.status == .error ? Color.orange : Color.lgMuted)
            Spacer()
            Label("About", systemImage: "info.circle")
            Label("Local-only", systemImage: "network.slash")
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.lgMuted)
        .padding(.horizontal, 32)
        .frame(height: 52)
        .background(Color.black.opacity(0.12))
        .overlay(alignment: .top) { Divider().overlay(Color.lgBorder) }
    }

    private var previewMetadata: String {
        let duration = viewModel.playbackDuration > 0
            ? String(format: "%.1fs", viewModel.playbackDuration)
            : "—"
        return "\(duration) • 44.1 kHz • Stereo"
    }

    private var waveformProgress: Double {
        guard viewModel.playbackDuration > 0 else { return 0 }
        return viewModel.playbackPosition / viewModel.playbackDuration
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.lgSecondary)
            .padding(.bottom, 11)
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct InstrumentButton: View {
    let instrument: InstrumentCategory
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: instrument.iconName)
                    .font(.system(size: 20, weight: .medium))
                Text(instrument.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .foregroundStyle(selected ? Color.white : Color.lgSecondary)
            .background(
                selected
                    ? LinearGradient(colors: [.lgPurple, .lgPurpleDark], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [.lgControlBackground, .lgControlBackground], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.lgPurpleBright.opacity(0.35) : Color.lgBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private extension InstrumentCategory {
    var iconName: String {
        switch self {
        case .synth: "waveform"
        case .bass: "music.note"
        case .drums: "circle.grid.cross"
        case .piano: "pianokeys"
        case .guitar: "guitars"
        case .strings: "music.quarternote.3"
        case .fx: "sparkles"
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .background(
                LinearGradient(
                    colors: [.lgPurpleBright, .lgPurpleDark],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(configuration.isPressed ? 0.72 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.38)
    }
}

private struct SecondaryIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.lgSecondary)
            .background(Color.lgControlBackground.opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.lgBorder, lineWidth: 1))
    }
}

private struct TransportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18))
            .foregroundStyle(Color.lgSecondary.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(width: 34, height: 34)
    }
}

private struct PlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .background(Color.lgControlBackground)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.lgPurpleBright, lineWidth: 2))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

private struct ExportButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.lgPurpleBright)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.lgPurple.opacity(configuration.isPressed ? 0.17 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.lgPurpleBright, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.36)
    }
}

extension Color {
    static let lgBackground = Color(red: 0.040, green: 0.052, blue: 0.068)
    static let lgBackgroundTop = Color(red: 0.055, green: 0.070, blue: 0.089)
    static let lgCardBackground = Color(red: 0.070, green: 0.085, blue: 0.105)
    static let lgControlBackground = Color(red: 0.052, green: 0.064, blue: 0.080)
    static let lgWaveformBackground = Color(red: 0.042, green: 0.052, blue: 0.066)
    static let lgBorder = Color.white.opacity(0.095)
    static let lgSecondary = Color(red: 0.72, green: 0.74, blue: 0.79)
    static let lgMuted = Color(red: 0.53, green: 0.56, blue: 0.62)
    static let lgPurple = Color(red: 0.42, green: 0.23, blue: 0.88)
    static let lgPurpleDark = Color(red: 0.28, green: 0.13, blue: 0.68)
    static let lgPurpleBright = Color(red: 0.58, green: 0.36, blue: 1.0)
}
