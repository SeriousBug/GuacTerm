import AppKit
import Carbon.HIToolbox

/// Registers a system-wide hotkey through Carbon's `RegisterEventHotKey`.
///
/// Carbon hotkeys are the one global shortcut mechanism on macOS that needs no
/// permission prompt: the system tells us when the combination fires instead of
/// letting us watch the keyboard. That matters for an app that should work the
/// moment it is dropped into /Applications.
@MainActor
final class GlobalHotKey {
    enum RegistrationFailure: LocalizedError {
        case alreadyTaken(String)
        case systemError(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .alreadyTaken(combo):
                "\(combo) is already used by another app."
            case let .systemError(status):
                "macOS refused the shortcut (error \(status))."
            }
        }
    }

    private static let signature: OSType = 0x4755_4143 // 'GUAC'
    private let identifier: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// Called on the main actor whenever the registered combination fires.
    var onPress: (() -> Void)?

    private(set) var registeredCombo: KeyCombo?

    func register(_ combo: KeyCombo) throws {
        unregister()
        installEventHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            // -9878 is eventHotKeyExistsErr: someone else owns the combo.
            if status == -9878 {
                throw RegistrationFailure.alreadyTaken(combo.displayString)
            }
            throw RegistrationFailure.systemError(status)
        }

        hotKeyRef = ref
        registeredCombo = combo
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        registeredCombo = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hotkey events on the main run loop.
                MainActor.assumeIsolated { hotKey.fire() }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerRef
        )
    }

    private func fire() {
        onPress?()
    }
}
