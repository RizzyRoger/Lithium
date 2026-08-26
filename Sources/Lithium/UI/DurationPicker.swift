import SwiftUI

/// Hours and minutes entry for a daily allowance.
struct DurationPicker: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            unit(label: "hours", value: $hours, range: 0...23)
            unit(label: "min", value: $minutes, range: 0...59, step: 5)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func unit(label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack(spacing: 4) {
            TextField("", value: clamped(value, to: range), format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .multilineTextAlignment(.trailing)
                .frame(width: 30)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12))
                )
            Stepper("") {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
            } onDecrement: {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
            }
            .labelsHidden()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    /// Keeps typed values inside range instead of letting "99" hours through.
    private func clamped(_ binding: Binding<Int>, to range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }
        )
    }
}
