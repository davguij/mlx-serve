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
    /// Slider half-range. Grows when a value outside it is entered and never
    /// shrinks, so the thumb does not jump under a drag.
    @State private var bound: Double

    init(lora: Binding<LoraAdapter>, remove: @escaping () -> Void) {
        _lora = lora
        self.remove = remove
        _bound = State(initialValue: LoraScale.sliderBound(for: lora.wrappedValue.scale))
    }

    var body: some View {
        let scale = Binding(get: { lora.scale }, set: { lora.scale = LoraScale.clamped($0) })
        let shown = max(bound, LoraScale.sliderBound(for: lora.scale))
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
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove this LoRA")
            }
            HStack(spacing: 8) {
                Text("Scale").font(.app(.rowTitle))
                Slider(value: scale, in: -shown...shown, step: LoraScale.sliderStep(bound: shown))
                // Fixed width: a field that sizes to its digits drags the
                // slider's right edge every time the value crosses a width.
                TextField("", value: scale, format: .number.grouping(.never).precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .font(.app(.caption).monospacedDigit())
                    .frame(width: 64)
                    .help("Strength. Negative values reverse the effect; type a value to go past the slider (±\(Int(LoraScale.limit)) max).")
            }
            .onChange(of: lora.scale) { _, value in bound = max(bound, LoraScale.sliderBound(for: value)) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: LoraWells.minHeight, alignment: .leading)
        .background(MediaDropWellBackground(isTargeted: false))
    }
}
