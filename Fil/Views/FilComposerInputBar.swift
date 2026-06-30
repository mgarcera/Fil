import SwiftUI
import PhotosUI

struct FilComposerInputBar: View {
    @Binding var text: String
    @Binding var selectedPhotos: [PhotosPickerItem]
    let stagedImageData: [Data]
    let placeholder: String
    let actionSymbol: String
    let secondaryActionSymbol: String?
    let isProcessing: Bool
    let autoFocus: Bool
    let onAction: () -> Void
    let onSecondaryAction: (() -> Void)?
    let onDismiss: (() -> Void)?
    let onFocusChange: ((Bool) -> Void)?
    let onRemoveStagedImage: (Int) -> Void

    @FocusState private var isFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !stagedImageData.isEmpty {
                stagedImageRow
            }

            HStack(alignment: .bottom, spacing: 10) {
                if let onDismiss {
                    Button {
                        isFocused = false
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 32, height: 32)
                            .background(Theme.background.opacity(0.55), in: Circle())
                    }
                }

                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 8, matching: .images) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 32, height: 32)
                        .background(Theme.background.opacity(0.55), in: Circle())
                }
                .disabled(isProcessing)

                ZStack(alignment: .leading) {
                    if trimmedText.isEmpty {
                        Text(placeholder)
                            .font(Theme.dmSans(15))
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.horizontal, 4)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $text, axis: .vertical)
                        .font(Theme.dmSans(15))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1...4)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(onAction)
                }
                .padding(.vertical, 8)

                if let secondaryActionSymbol, let onSecondaryAction {
                    Button(action: onSecondaryAction) {
                        Image(systemName: secondaryActionSymbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 34, height: 34)
                            .background(Theme.background, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(Theme.divider.opacity(0.55), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedText.isEmpty || isProcessing || !stagedImageData.isEmpty)
                    .opacity(trimmedText.isEmpty || isProcessing || !stagedImageData.isEmpty ? 0.45 : 1)
                }

                Button(action: onAction) {
                    Group {
                        if isProcessing {
                            ProgressView()
                                .tint(Theme.primaryText)
                        } else {
                            Image(systemName: actionSymbol)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.primaryText)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .borderBeam(
                        border: Theme.primaryText,
                        beam: Theme.accentGradientColors,
                        beamBlur: 6,
                        cornerRadius: 17,
                        isEnabled: isFocused || !trimmedText.isEmpty || isProcessing
                    )
                    .background(Theme.background, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Theme.divider.opacity(0.55), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(trimmedText.isEmpty || isProcessing)
                .opacity(trimmedText.isEmpty || isProcessing ? 0.65 : 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.divider.opacity(0.55), lineWidth: 1)
        }
        .onAppear {
            guard autoFocus else { return }
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onChange(of: isFocused) { _, isFocused in
            onFocusChange?(isFocused)
        }
    }

    private var stagedImageRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(stagedImageData.enumerated()), id: \.offset) { index, data in
                    stagedImageThumbnail(data: data, index: index)
                }
            }
            .padding(.leading, onDismiss == nil ? 0 : 42)
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
