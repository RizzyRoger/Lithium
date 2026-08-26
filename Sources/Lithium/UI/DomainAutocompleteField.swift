import SwiftUI

/// Text field for entering a site, with inline suggestions from `TopSites`.
struct DomainAutocompleteField: View {
    @Binding var text: String
    let recents: [String]
    /// Called when the user presses Return on the field itself.
    var onSubmit: () -> Void

    @State private var highlighted: Int = 0
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    private var suggestions: [String] {
        guard isEditing, isFocused, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let all = TopSites.suggestions(for: text, recents: recents)
        // Nothing to offer when the only suggestion is exactly what is typed.
        if all.count == 1, all[0] == DomainMatcher.normalize(userInput: text) { return [] }
        return all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            field
            if !suggestions.isEmpty {
                suggestionList
            }
        }
    }

    /// Typing reopens the suggestion list; selecting one closes it.
    private var editingText: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                text = newValue
                isEditing = true
                highlighted = 0
            }
        )
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
            TextField("Site, for example tiktok.com", text: editingText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit { commitReturn() }
                .modifier(SuggestionKeyHandling(
                    hasSuggestions: !suggestions.isEmpty,
                    onMove: moveHighlight,
                    onDismiss: { isEditing = false }
                ))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12))
        )
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                Button {
                    accept(suggestion)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: recents.contains(suggestion) ? "clock.arrow.circlepath" : "magnifyingglass")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(suggestion)
                            .font(.system(size: 12))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(index == highlighted ? Color.accentColor.opacity(0.18) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
    }

    private func moveHighlight(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        let count = suggestions.count
        highlighted = ((highlighted + delta) % count + count) % count
    }

    private func accept(_ suggestion: String) {
        text = suggestion
        isEditing = false
        highlighted = 0
    }

    private func commitReturn() {
        // Return accepts the highlighted suggestion first, then adds the rule.
        if !suggestions.isEmpty, highlighted < suggestions.count {
            accept(suggestions[highlighted])
            return
        }
        isEditing = false
        onSubmit()
    }

    /// Best interpretation of free text: the text itself if it is a domain,
    /// otherwise the top suggestion.
    static func resolve(_ text: String, recents: [String]) -> String? {
        if let normalized = DomainMatcher.normalize(userInput: text) { return normalized }
        return TopSites.suggestions(for: text, recents: recents, limit: 1).first
    }
}

/// Arrow-key navigation needs `onKeyPress`, which is macOS 14 and later. On macOS
/// 13 the list stays clickable and Return still accepts the first suggestion.
private struct SuggestionKeyHandling: ViewModifier {
    let hasSuggestions: Bool
    let onMove: (Int) -> Void
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.downArrow) {
                    guard hasSuggestions else { return .ignored }
                    onMove(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard hasSuggestions else { return .ignored }
                    onMove(-1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard hasSuggestions else { return .ignored }
                    onDismiss()
                    return .handled
                }
        } else {
            content
        }
    }
}
