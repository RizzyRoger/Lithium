import AppKit
import SwiftUI

/// Contents of the menu bar popover: two sections plus status and settings.
struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                PopoverContentView(model: model)
            }
            .frame(maxHeight: 460)

            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Lithium")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(model.statusLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.blockPagePort == nil ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(model.blockPagePort == nil ? "Block page unavailable" : "Watching every second")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Menu {
                Toggle("Hard blocking via /etc/hosts", isOn: hostsBinding)
                    .disabled(!model.helperStatus.isFullyInstalled)
                Toggle("Launch at login", isOn: loginItemBinding)

                Divider()

                if model.helperStatus.isFullyInstalled {
                    Button("Remove hard blocking helper…") { model.uninstallHelper() }
                } else {
                    Button("Install hard blocking helper…") { model.installHelper() }
                }
                Button("Preview block page") { previewBlockPage() }
                Button("Open log file") { NSWorkspace.shared.open(Paths.logFile) }

                Divider()

                Button("Quit Lithium") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var hostsBinding: Binding<Bool> {
        Binding(
            get: { model.config.hostsEnforcementEnabled },
            set: { newValue in
                model.config.hostsEnforcementEnabled = newValue
                model.syncHosts(force: true)
            }
        )
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { model.config.launchAtLogin },
            set: { newValue in
                model.config.launchAtLogin = newValue
                LoginItem.setEnabled(newValue)
            }
        )
    }

    private func previewBlockPage() {
        guard let port = model.blockPagePort else {
            Log.error(.ui, "cannot preview block page: server is not running")
            return
        }
        let domain = model.config.rules.first?.domain ?? "example.com"
        guard let url = URL(string: "http://127.0.0.1:\(port)/blocked?d=\(domain)&r=ban&used=0") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The scrolling part of the popover: warnings plus the two sections. Split out so
/// it can be rendered on its own, since `ImageRenderer` cannot draw `ScrollView`
/// contents.
struct PopoverContentView: View {
    @ObservedObject var model: AppModel

    @State private var restrictionsExpanded = true
    @State private var presetsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banners
            RestrictionsSection(model: model, isExpanded: $restrictionsExpanded)
            Divider().padding(.horizontal, 12)
            PresetsSection(model: model, isExpanded: $presetsExpanded)
        }
    }

    @ViewBuilder
    private var banners: some View {
        if !model.automationDeniedBrowsers.isEmpty {
            Banner(
                icon: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "Automation access needed",
                message: "Lithium cannot read tabs in \(model.automationDeniedBrowsers.sorted().joined(separator: ", ")), so time is not being counted.",
                actionTitle: "Open Settings",
                action: openAutomationSettings,
                secondaryTitle: "Recheck",
                secondaryAction: model.recheckAutomationPermission
            )
        }

        if !model.helperStatus.isFullyInstalled {
            Banner(
                icon: "lock.shield",
                tint: .blue,
                title: "Hard blocking is off",
                message: "Blocked sites are redirected in scriptable browsers only. Installing the helper also blocks them at the DNS level in every browser.",
                actionTitle: model.helperBusy ? "Working…" : "Enable",
                action: model.installHelper,
                actionDisabled: model.helperBusy
            )
        }

        if let message = model.helperMessage {
            Banner(
                icon: "info.circle",
                tint: .secondary,
                title: message,
                message: nil,
                actionTitle: "Dismiss",
                action: { model.helperMessage = nil }
            )
        }
    }

    private func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        if let url { NSWorkspace.shared.open(url) }
    }
}

private struct Banner: View {
    let icon: String
    let tint: Color
    let title: String
    var message: String?
    let actionTitle: String
    let action: () -> Void
    var actionDisabled: Bool = false
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button(actionTitle, action: action)
                        .font(.system(size: 11))
                        .disabled(actionDisabled)
                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle, action: secondaryAction)
                            .font(.system(size: 11))
                    }
                }
                .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.22))
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
