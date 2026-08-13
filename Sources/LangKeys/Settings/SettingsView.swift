import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs = Preferences.shared
    @State private var sources: [InputSource] = InputSourceManager.available()
    @State private var isAccessibilityTrusted = AXIsProcessTrusted()

    var onOpenAccessibilitySettings: () -> Void = {}
    var onQuit: () -> Void = {}

    private let permissionTick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if !isAccessibilityTrusted {
                permissionBanner
                    .padding([.horizontal, .top], 14)
            }

            TabView {
                keysTab
                    .tabItem { Label("Keys", systemImage: "keyboard") }
                notchTab
                    .tabItem { Label("Notch", systemImage: "rectangle.topthird.inset.filled") }
                generalTab
                    .tabItem { Label("General", systemImage: "gearshape") }
            }
            .padding(14)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onReceive(permissionTick) { _ in
            isAccessibilityTrusted = AXIsProcessTrusted()
            sources = InputSourceManager.available()
        }
    }

    // MARK: - Banner

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission needed").fontWeight(.medium)
                Text("LangKeys cannot see your key taps until it is allowed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings", action: onOpenAccessibilitySettings)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Tabs

    private var keysTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tap a key on its own to switch input source.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(ModifierKey.allCases, id: \.rawValue) { key in
                    HStack(spacing: 10) {
                        Text(key.title)
                            .frame(width: 140, alignment: .leading)

                        Picker("", selection: sourceBinding(for: key)) {
                            Text("None").tag(String?.none)
                            ForEach(sources, id: \.id) { source in
                                Text(source.displayName).tag(String?.some(source.id))
                            }
                        }
                        .labelsHidden()

                        Picker("", selection: sideBinding(for: key)) {
                            Text("Left").tag(NotchSide.left)
                            Text("Right").tag(NotchSide.right)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                        .disabled(prefs.mappings[key] == nil || !prefs.showsNotchHUD)
                        .help("Which side of the notch this key's flag appears on")
                    }
                }
            }
            .padding(14)
        }
    }

    private var notchTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Show the flag in the notch", isOn: $prefs.showsNotchHUD)

            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $prefs.flagStaysVisible) {
                    Text("Stays visible, so the current input is always shown").tag(true)
                    Text("Disappears after a moment").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                if !prefs.flagStaysVisible {
                    HStack {
                        Text("Hide after")
                        Slider(value: $prefs.flagDwellSeconds, in: 0.5...6, step: 0.1)
                        Text("\(prefs.flagDwellSeconds, specifier: "%.1f")s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .padding(.leading, 20)
                }
            }
            .disabled(!prefs.showsNotchHUD)

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Switch input source on key taps", isOn: $prefs.isEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show the menu bar icon", isOn: $prefs.showsMenuBarIcon)
                Text(
                    "With the menu bar icon hidden, open these settings again from Spotlight or "
                        + "the Applications folder."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Open at login", isOn: launchAtLoginBinding)

            Spacer()

            HStack {
                Spacer()
                Button("Quit LangKeys", action: onQuit)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bindings

    private func sourceBinding(for key: ModifierKey) -> Binding<String?> {
        Binding(
            get: { prefs.inputSourceID(for: key) },
            set: { prefs.setInputSource($0, for: key) })
    }

    private func sideBinding(for key: ModifierKey) -> Binding<NotchSide> {
        Binding(
            get: { prefs.notchSide(for: key) },
            set: { prefs.setNotchSide($0, for: key) })
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { LoginItem.isEnabled },
            set: { LoginItem.setEnabled($0) })
    }
}
