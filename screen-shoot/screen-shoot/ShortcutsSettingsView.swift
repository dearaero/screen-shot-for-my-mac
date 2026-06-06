import SwiftUI
import AppKit

struct ShortcutsSettingsView: View {

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ShortcutAction.allCases, id: \.self) { action in
                        ShortcutRow(action: action)
                    }
                }
            } header: {
                HStack {
                    Text("Keyboard Shortcuts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Defaults") {
                        ShortcutStore.shared.resetToDefaults()
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(20)
    }
}

struct ShortcutRow: View {

    let action: ShortcutAction
    @State private var config: ShortcutConfig
    @State private var isRecording = false

    init(action: ShortcutAction) {
        self.action = action
        _config = State(initialValue: ShortcutStore.shared.config(for: action) ?? ShortcutConfig(
            action: action.rawValue,
            keyCode: action.defaultKeyCode,
            modifierFlags: action.defaultModifiers.rawValue,
            isEnabled: true
        ))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(action.displayName)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRecording {
                Text("Press keys...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.1))
                    )
            } else {
                Text(config.displayString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
            }

            Button(isRecording ? "Cancel" : "Record") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .controlSize(.small)
        }
        .frame(height: 32)
    }

    private func startRecording() {
        isRecording = true
        ShortcutRecorder.shared.startRecording { keyCode, modifiers in
            ShortcutStore.shared.update(action: action, keyCode: keyCode, modifiers: modifiers)
            if let updated = ShortcutStore.shared.config(for: action) {
                config = updated
            }
            isRecording = false
        }
    }

    private func stopRecording() {
        ShortcutRecorder.shared.stopRecording()
        isRecording = false
    }
}

// MARK: - Shortcut Recorder

final class ShortcutRecorder {

    static let shared = ShortcutRecorder()

    private let lock = NSLock()
    private var keyDownMonitor: Any?
    private var flagsChangedMonitor: Any?
    private var onComplete: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    func startRecording(completion: @escaping (UInt16, NSEvent.ModifierFlags) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        stopRecordingLocked()
        onComplete = completion

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
            return nil
        }

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            return event
        }
    }

    func stopRecording() {
        lock.lock()
        defer { lock.unlock() }
        stopRecordingLocked()
    }

    private func stopRecordingLocked() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        onComplete = nil
    }

    private func handleEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        let requiredModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard !modifiers.intersection(requiredModifiers).isEmpty else { return }

        let modifierOnlyKeys: [UInt16] = [0x37, 0x38, 0x3A, 0x3B]
        guard !modifierOnlyKeys.contains(keyCode) else { return }

        lock.lock()
        let completion = onComplete
        onComplete = nil
        lock.unlock()

        completion?(keyCode, modifiers)
        stopRecording()
    }
}
