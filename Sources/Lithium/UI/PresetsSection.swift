import SwiftUI

/// Bottom section: save the current rule set under a name and swap between them.
struct PresetsSection: View {
    @ObservedObject var model: AppModel
    @Binding var isExpanded: Bool

    @State private var presetName: String = ""

    var body: some View {
        SectionCard(
            title: "Presets",
            subtitle: subtitle,
            systemImage: "square.stack.3d.up",
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    TextField("Preset name", text: $presetName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12))
                        )
                        .onSubmit(save)

                    Button(action: save) {
                        Text(willOverwrite ? "Overwrite" : "Save")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Text("Saves the \(model.config.rules.count) current rule\(model.config.rules.count == 1 ? "" : "s") as a preset you can switch back to.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if model.config.presets.isEmpty {
                    Text("No presets saved yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } else {
                    Divider().padding(.vertical, 2)
                    VStack(spacing: 4) {
                        ForEach(model.config.presets) { preset in
                            PresetRow(
                                preset: preset,
                                isActive: model.config.activePresetID == preset.id,
                                onApply: { model.applyPreset(preset) },
                                onDelete: { model.deletePreset(preset) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        if let id = model.config.activePresetID,
           let active = model.config.presets.first(where: { $0.id == id }) {
            return "Using \(active.name)"
        }
        if model.config.presets.isEmpty { return "Save the current config" }
        return "\(model.config.presets.count) saved"
    }

    private var willOverwrite: Bool {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return model.config.presets.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private func save() {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.savePreset(named: trimmed)
        presetName = ""
    }
}

private struct PresetRow: View {
    let preset: Preset
    let isActive: Bool
    let onApply: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.6))
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                Text(preset.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isHovering {
                Button("Apply", action: onApply)
                    .font(.system(size: 11))
                    .buttonStyle(.borderless)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Delete this preset")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onApply)
        .onHover { isHovering = $0 }
    }
}
