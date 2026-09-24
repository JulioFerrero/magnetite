import Carbon.HIToolbox
import MagnetiteCore

final class HotKey {
    private var hotKeyRef: EventHotKeyRef?, handlerRef: EventHandlerRef?
    private let action: () -> Void
    init?(combo: KeyCombo, action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, me in
            if let me { Unmanaged<HotKey>.fromOpaque(me).takeUnretainedValue().action() }
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), handler, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handlerRef) == noErr,
              RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: 0x4D47_4E54, id: 1), GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
        else { return nil }
    }
    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
