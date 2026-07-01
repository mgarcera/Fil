import SwiftUI
import PhotosUI

/// The single, always-on composer bar. It shifts between three states in place:
/// idle (placeholder + mic), typing (text field + send), and recording (waveform + stop).
struct ComposerBar: View {
    @Binding var text: String
    @Binding var selectedPhotos: [PhotosPickerItem]
    let stagedImageData: [Data]
    let isRecording: Bool
    let recordingDuration: TimeInterval
    let isProcessing: Bool
    var focus: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onRemoveStagedImage: (Int) -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasText: Bool { !trimmedText.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !stagedImageData.isEmpty && !isRecording {
                stagedImageRow
            }

            HStack(alignment: .bottom, spacing: 10) {
                if !isRecording {
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 8, matching: .images) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .disabled(isProcessing)
                }

                inputArea

                trailingButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            if !isRecording {
                focus.wrappedValue = true
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isRecording)
    }

    @ViewBuilder
    private var inputArea: some View {
        if isRecording {
            WaveformView(duration: recordingDuration, isAnimating: true, fillsWidth: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            ZStack(alignment: .leading) {
                if trimmedText.isEmpty {
                    Text("tap to write")
                        .font(Theme.dmSans(15))
                        .foregroundStyle(Theme.tertiaryText)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text, axis: .vertical)
                    .font(Theme.dmSans(15))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1...4)
                    .focused(focus)
                    .submitLabel(.return)
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if isRecording {
            Button(action: onStopRecording) {
                beamedCircle(symbol: "stop.fill", weight: .semibold)
            }
            .buttonStyle(.plain)
        } else if hasText {
            Button(action: onSend) {
                beamedCircle(symbol: "arrow.up", weight: .bold)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        } else {
            Button(action: onStartRecording) {
                filledCircle(symbol: "mic.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private func filledCircle(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.background)
            .frame(width: 36, height: 36)
            .background(Theme.primaryText, in: Circle())
    }

    /// A filled prominent circle with the animated accent border beam (send / stop).
    /// The beam is applied before the fill so it renders in front of the circle.
    private func beamedCircle(symbol: String, weight: Font.Weight) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: weight))
            .foregroundStyle(Theme.background)
            .frame(width: 36, height: 36)
            .borderBeam(
                border: Theme.primaryText,
                beam: Theme.accentGradientColors,
                beamBlur: 6,
                cornerRadius: 18,
                isEnabled: true
            )
            .background(Theme.primaryText, in: Circle())
    }

    private var stagedImageRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(stagedImageData.enumerated()), id: \.offset) { index, data in
                    stagedImageThumbnail(data: data, index: index)
                }
            }
            .padding(.leading, 40)
            .padding(.trailing, 4)
        }
    }

    @ViewBuilder
    private func stagedImageThumbnail(data: Data, index: Int) -> some View {
        if let image = Image(data: data) {
            image
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        onRemoveStagedImage(index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 14, height: 14)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                }
        }
    }
}
