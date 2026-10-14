import SwiftUI

/// The Style LoRAs block the Image and Video panes share: one well per
/// attached adapter with its scale, and the add well under the last one.
enum LoraWells {
    /// Thinner than the image wells' 84: two lines of text, not a thumbnail.
    static let minHeight: CGFloat = 64
}

/// Click-only: a LoRA is picked from a file panel, and a well that accepts a
/// drag is a promise this one does not keep.
struct LoraAddWell: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MediaWellAction(title: "Choose .safetensors…",
                            systemImage: "paintpalette",
                            caption: "Add LoRA adapter for custom style. Several can stack at once.")
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: LoraWells.minHeight, alignment: .center)
            .background(MediaDropWellBackground(isTargeted: false))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One attached adapter: its file name, its scale and the way out.
struct LoraAdapterRow: View {
    @Binding var lora: LoraAdapter
    let remove: () -> Void
    @State private var editingRange = false
    // The field keeps what was typed even when the binding clamps it; rebuilding it on commit shows the value in use.
    @State private var fieldEpoch = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let range = lora.range
        let scale = Binding(get: { lora.scale }, set: { lora.scale = range.clamped($0) })
        let rangeBinding = Binding(get: { lora.range }, set: { newRange in
            lora.range = newRange
            lora.scale = newRange.clamped(lora.scale)
            LoraRangeMemory.remember(newRange, path: lora.path)
        })
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette")
                    .foregroundStyle(.secondary)
                Text(URL(fileURLWithPath: lora.path).lastPathComponent)
                    .font(.app(.caption))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(lora.path)
                Spacer()
                Button { editingRange = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Strength range for this LoRA")
                .popover(isPresented: $editingRange) {
                    LoraRangeEditor(range: rangeBinding).padding(12)
                }
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this LoRA")
            }
            HStack(spacing: 8) {
                Text("Scale").font(.app(.rowTitle))
                Slider(value: scale, in: range.sliderRange, step: range.sliderStep)
                // Fixed width: a field that sizes to its digits drags the
                // slider's right edge every time the value crosses a width.
                TextField("", value: scale, format: .number.grouping(.never).precision(.fractionLength(0...2)))
                    .id(fieldEpoch)
                    .focused($fieldFocused)
                    .onSubmit { fieldFocused = false }
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused { DispatchQueue.main.async { fieldEpoch += 1 } }
                    }
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.app(.caption).monospacedDigit())
                    .frame(width: 64)
                    .help(range.signed
                        ? "Strength. Negative values reverse the effect; type a value to go past the slider (±\(Int(LoraRange.limit)) max)."
                        : "Strength, 0 or more; type a value to go past the slider (\(Int(LoraRange.limit)) max). A LoRA that takes negative values needs the range button.")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: LoraWells.minHeight, alignment: .leading)
        .background(MediaDropWellBackground(isTargeted: false))
    }
}

/// Regular (0 to 2) or negatable (-X to X) for one adapter. Only the slider's span and
/// the field's sign depend on it; the number field always accepts values far past the slider.
private struct LoraRangeEditor: View {
    @Binding var range: LoraRange

    var body: some View {
        let mode = Binding(get: { range.signed }, set: { range = $0 ? .negatable() : .regular })
        let bound = Binding(get: { range.bound },
                            set: { range = .negatable(min(LoraRange.limit, max(0.1, $0))) })
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: mode) {
                Text("Regular").tag(false)
                Text("Negatable").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if range.signed {
                HStack(spacing: 6) {
                    Text("Slider spans ±").font(.app(.caption))
                    TextField("", value: bound, format: .number.grouping(.never).precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .font(.app(.caption).monospacedDigit())
                        .frame(width: 56)
                }
            } else {
                Text("Slider spans 0 to 2.").font(.app(.caption))
            }
            Text("Remembered for this file. The number field accepts up to \(Int(LoraRange.limit)) either way; only negative values need Negatable.")
                .font(.app(.caption))
                .foregroundStyle(.secondary)
                .frame(width: 240, alignment: .leading)
        }
    }
}
