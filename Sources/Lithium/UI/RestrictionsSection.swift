import SwiftUI

/// Top section: add or edit a restriction, and see today's usage per site.
struct RestrictionsSection: View {
    @ObservedObject var model: AppModel
    @Binding var isExpanded: Bool

    @State private var domainText: String = ""
    @State private var hours: Int = 0
    @State private var minutes: Int = 30
    @State private var banAllDay: Bool = false
    @State private var errorText: String?

    var body: some View {
        SectionCard(
            title: "Set restrictions",
            subtitle: summary,
            systemImage: "hourglass",
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                DomainAutocompleteField(
                    text: $domainText,
                    recents: model.config.recentDomains,
                    onSubmit: addRule
                )

                Toggle(isOn: $banAllDay) {
                    Text("Ban for the whole day")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)

                HStack {
                    DurationPicker(hours: $hours, minutes: $minutes, isEnabled: !banAllDay)
                    Spacer()
                    Button(action: addRule) {
                        Text(isEditingExisting ? "Update" : "Add")
                            .font(.system(size: 12, weight: .medium))
                            .frame(minWidth: 46)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                if model.config.rules.isEmpty {
                    Text("No limits yet. Sites without a rule are never restricted.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } else {
                    Divider().padding(.vertical, 2)
                    VStack(spacing: 6) {
                        ForEach(model.config.rules) { rule in
                            RuleRow(model: model, rule: rule, onEdit: { load(rule) })
                        }
                    }
                }
            }
        }
    }

    private var summary: String {
        let rules = model.config.rules
        guard !rules.isEmpty else { return "Nothing limited" }
        let blocked = rules.filter { model.isBlockedNow($0) }.count
        if blocked > 0 {
            return "\(rules.count) site\(rules.count == 1 ? "" : "s") · \(blocked) blocked now"
        }
        return "\(rules.count) site\(rules.count == 1 ? "" : "s") limited"
    }

    private var resolvedDomain: String? {
        DomainAutocompleteField.resolve(domainText, recents: model.config.recentDomains)
    }

    private var isEditingExisting: Bool {
        guard let domain = resolvedDomain else { return false }
        return model.config.rules.contains { $0.domain == domain }
    }

    private var canAdd: Bool {
        guard resolvedDomain != nil else { return false }
        return banAllDay || hours > 0 || minutes > 0
    }

    private func addRule() {
        guard let domain = resolvedDomain else {
            errorText = "That does not look like a site address."
            return
        }
        guard banAllDay || hours > 0 || minutes > 0 else {
            errorText = "Set a duration, or choose to ban for the day."
            return
        }
        errorText = nil
        let limit: TimeInterval? = banAllDay ? nil : TimeInterval(hours * 3600 + minutes * 60)
        model.addRule(domain: domain, limit: limit)
        domainText = ""
        banAllDay = false
    }

    private func load(_ rule: SiteRule) {
        domainText = rule.domain
        if let limit = rule.dailyLimit {
            banAllDay = false
            hours = Int(limit) / 3600
            minutes = (Int(limit) % 3600) / 60
        } else {
            banAllDay = true
        }
        errorText = nil
    }
}

/// One site's limit and today's progress against it.
private struct RuleRow: View {
    @ObservedObject var model: AppModel
    let rule: SiteRule
    let onEdit: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(rule.domain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(rule.enabled ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(detailText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if isHovering {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("Edit this limit")

                    Button {
                        model.setEnabled(!rule.enabled, for: rule)
                    } label: {
                        Image(systemName: rule.enabled ? "pause.circle" : "play.circle")
                    }
                    .buttonStyle(.plain)
                    .help(rule.enabled ? "Pause this rule" : "Resume this rule")

                    if model.spent(on: rule) > 0 {
                        Button {
                            model.resetUsage(for: rule)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.plain)
                        .help("Reset today's usage")
                    }

                    Button {
                        model.removeRule(rule)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Remove this rule")
                }
            }
            .font(.system(size: 10))

            if !rule.isBanned {
                ProgressView(value: model.progress(for: rule))
                    .progressViewStyle(.linear)
                    .tint(statusColor)
                    .frame(height: 3)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .onHover { isHovering = $0 }
    }

    private var statusColor: Color {
        if !rule.enabled { return .gray }
        if model.isBlockedNow(rule) { return .red }
        return model.progress(for: rule) > 0.75 ? .orange : .green
    }

    private var detailText: String {
        if !rule.enabled { return "paused" }
        if rule.isBanned { return "banned" }
        let spent = model.spent(on: rule)
        return "\(SiteRule.format(seconds: spent)) / \(rule.limitDescription)"
    }
}
