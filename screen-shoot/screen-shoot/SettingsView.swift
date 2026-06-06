import SwiftUI

struct SettingsView: View {

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            CustomizationSettingsView()
                .tabItem {
                    Label("Customization", systemImage: "paintpalette")
                }
        }
        .frame(width: 520, height: 340)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {

    @State private var thumbnailCorner: ThumbnailCorner = .bottomLeft
    @State private var saveLocation: SaveLocation = .desktop
    @State private var customSaveDirectory: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Thumbnail Position
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thumbnail Position")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Choose where the screenshot thumbnail appears on screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                CornerPickerView(
                    selectedCorner: $thumbnailCorner,
                    onChange: { newValue in
                        SettingsStore.shared.setThumbnailCorner(newValue)
                    }
                )
            }

            Divider()

            // Save Location
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Save Location")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Where screenshots are saved when captured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Save to", selection: $saveLocation) {
                    ForEach(SaveLocation.allCases, id: \.self) { location in
                        Label(location.displayName, systemImage: location.systemImage)
                            .tag(location)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .onChange(of: saveLocation) { _, newValue in
                    SettingsStore.shared.setSaveLocation(newValue)
                }

                if saveLocation == .custom {
                    HStack(spacing: 8) {
                        Text(customSaveDirectory.isEmpty
                             ? "No folder selected"
                             : URL(fileURLWithPath: customSaveDirectory).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(customSaveDirectory.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Choose...") {
                            chooseCustomDirectory()
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                }

                if saveLocation == .clipboardOnly {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text("Screenshots will only be copied to the clipboard. No file will be saved to disk.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            loadSettings()
        }
    }

    private func loadSettings() {
        let store = SettingsStore.shared
        thumbnailCorner = store.thumbnailCorner
        saveLocation = store.saveLocation
        customSaveDirectory = store.customSaveDirectory
    }

    private func chooseCustomDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Save Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if !customSaveDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: customSaveDirectory)
        }

        if panel.runModal() == .OK, let url = panel.url {
            customSaveDirectory = url.path
            SettingsStore.shared.setCustomSaveDirectory(url.path)
        }
    }
}

// MARK: - Corner Picker

struct CornerPickerView: View {

    @Binding var selectedCorner: ThumbnailCorner
    var onChange: ((ThumbnailCorner) -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                cornerButton(.topLeft)
                cornerButton(.topRight)
            }
            HStack(spacing: 4) {
                cornerButton(.bottomLeft)
                cornerButton(.bottomRight)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func cornerButton(_ corner: ThumbnailCorner) -> some View {
        let isSelected = selectedCorner == corner

        return Button {
            selectedCorner = corner
            onChange?(corner)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(nsColor: .controlBackgroundColor))

                Image(systemName: corner.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .frame(width: 80, height: 56)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(corner.displayName)
    }
}

// MARK: - Customization Settings

struct CustomizationSettingsView: View {

    @State private var isRainbowMode: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Rainbow Mode
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rainbow Mode")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Each screenshot thumbnail gets a unique vibrant color border.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $isRainbowMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: isRainbowMode) { _, newValue in
                        SettingsStore.shared.setRainbowMode(newValue)
                    }
            }

            if isRainbowMode {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Thumbnails will cycle through red, orange, yellow, green, blue, and purple.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            isRainbowMode = SettingsStore.shared.isRainbowMode
        }
    }
}

#Preview {
    SettingsView()
}
