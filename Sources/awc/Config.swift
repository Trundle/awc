import Foundation

import awc_config
import Wlroots

private extension AwcColor {
    func toFloatRgba() -> float_rgba {
        float_rgba(r: Float(self.r) / 255.0, g: Float(self.g) / 255.0, b: Float(self.b) / 255.0, a: Float(self.a) / 255.0)
    }
}

public enum Action {
    /// Close focused surface
    case close
    case configReload
    case execute(cmd: String)
    /// Move focus to next surface
    case focusDown
    /// Move focus to previous surface
    case focusUp
    /// Focus primary window
    case focusPrimary
    /// Focus output n
    case focusOutput(n: UInt8)
    /// Swap the focused surface with the next surface
    case swapDown
    //[ Swap the focused surface with the previous surface
    case swapUp
    /// Swap the focused surface and the primary surface
    case swapPrimary
    /// Move focused surface to workspace with the given tag
    case moveTo(tag: String)
    /// Move focused surface to output n
    case moveToOutput(n: UInt8)
    case nextLayout
    /// Push focused surface back into tiling
    case sink
    /// Swap workspaces on primary and secondary output
    case swapWorkspaces
    case switchVt(n: UInt8)
    /// Switch to the workspace with the given tag
    case view(tag: String)
}

public enum ButtonAction {
    case move
    case resize
}

enum Key: Hashable {
    case code(code: UInt32)
    case sym(sym: xkb_keysym_t)
}

public struct ButtonActionKey: Hashable {
    let modifiers: KeyModifiers
    let button: UInt32
}

private struct KeyActionKey: Hashable {
    let modifiers: KeyModifiers
    let key: Key
}

class Config {
    let borderWidth: UInt32
    let activeBorderColor: float_rgba
    let inactiveBorderColor: float_rgba
    let outputConfigs: [String: (Int32, Int32, Float)]
    private let buttonBindings: [ButtonActionKey: ButtonAction]
    private let keyBindings: [KeyActionKey: Action]
    fileprivate let token: UnsafeMutableRawPointer

    deinit {
        awcConfigRelease(self.token)
    }

    fileprivate init(
        token: UnsafeMutableRawPointer,
        borderWidth: UInt32,
        activeBorderColor: float_rgba,
        inactiveBorderColor: float_rgba,
        buttonBindings: [ButtonActionKey: ButtonAction],
        keyBindings: [KeyActionKey: Action],
        outputConfigs: [String: (Int32, Int32, Float)]
    ) {
        self.token = token
        self.borderWidth = borderWidth
        self.activeBorderColor = activeBorderColor
        self.inactiveBorderColor = inactiveBorderColor
        self.buttonBindings = buttonBindings
        self.keyBindings = keyBindings
        self.outputConfigs = outputConfigs
    }

    func configureKeyboard(vendor: UInt32) -> String {
        var keyboardConfig = AwcKeyboardConfig()
        defer {
            free(keyboardConfig.Layout)
        }
        awcConfigureKeyboard(vendor, self.token, &keyboardConfig)
        return String(cString: keyboardConfig.Layout)
    }

    func generateErrorDisplayCmd(msg: String) -> String {
        let cmd = msg.withCString {
            awcGenerateErrorDisplayCmd($0, self.token)
        }
        defer {
            free(cmd)
        }
        return String(cString: cmd!)
    }

    func findButtonBinding(modifiers: KeyModifiers, button: UInt32) -> ButtonAction? {
        return self.buttonBindings[ButtonActionKey(modifiers: modifiers, button: button)]
    }

    func findKeyBinding(modifiers: KeyModifiers, code: UInt32, sym: xkb_keysym_t) -> Action? {
        if let action = self.keyBindings[KeyActionKey(modifiers: modifiers, key: Key.sym(sym: sym))] {
            return action
        } else if let action = self.keyBindings[KeyActionKey(modifiers: modifiers, key: Key.code(code: code))] {
            return action
        }
        return nil
    }
}

func loadConfig() -> Config? {
    var config = AwcConfig()

    if let error = awcLoadConfig(nil, &config) {
        print("[FATAL] Could not load config: \(String(cString: error))")
        free(error)
        return nil
    }
    defer {
        awcConfigFree(&config)
    }

    var buttonBindings: [ButtonActionKey: ButtonAction] = [:]
    for i in 0..<config.numberOfButtonBindings {
        let actionKey = ButtonActionKey(
            modifiers: KeyModifiers(rawValue: config.buttonBindings[i].mods),
            button: toButton(config.buttonBindings[i].button)
        )
        buttonBindings[actionKey] = toButtonAction(&config.buttonBindings[i].action)
    }

    var keyBindings: [KeyActionKey: Action] = [:]
    for i in 0..<config.numberOfKeyBindings {
        let key: Key
        if let sym = config.keyBindings[i].sym {
            let keySym = xkb_keysym_from_name(sym, XKB_KEYSYM_NO_FLAGS)
            if keySym == 0 {
                print("[WARN] Unknown key symbol: \(String(cString: sym))")
                continue
            }
            key = Key.sym(sym: keySym)
        } else {
            assert(config.keyBindings[i].code != 0)
            key = Key.code(code: config.keyBindings[i].code)
        }
        let actionKey = KeyActionKey(
            modifiers: KeyModifiers(rawValue: config.keyBindings[i].mods),
            key: key
        )
        keyBindings[actionKey] = toAction(&config.keyBindings[i].action)
    }

    var outputConfigs: [String: (Int32, Int32, Float)] = [:]
    for i in 0..<config.numberOfOutputs {
        let scale: Float = config.outputs[i].scale
        outputConfigs[String(cString: config.outputs[i].name)] =
            (config.outputs[i].x, config.outputs[i].y, scale)
    }

    return Config(
        token: config.token,
        borderWidth: config.borderWidth,
        activeBorderColor: config.activeBorderColor.toFloatRgba(),
        inactiveBorderColor: config.inactiveBorderColor.toFloatRgba(),
        buttonBindings: buttonBindings,
        keyBindings: keyBindings,
        outputConfigs: outputConfigs
    )
}

private func toAction(_ action: inout AwcAction) -> Action {
    if let execute = action.execute {
        assert(action.switchVt == 0)
        assert(!action.focusDown)
        assert(!action.focusUp)
        assert(!action.focusPrimary)
        assert(!action.sink)
        assert(!action.swapDown)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.swapWorkspaces)
        assert(!action.nextLayout)
        assert(action.moveTo == nil)
        assert(action.view == nil)
        assert(action.focusOutput == 0)
        assert(action.moveToOutput == 0)
        assert(action.switchVt == 0)
        return .execute(cmd: String(cString: execute))
    } else if let tag = action.moveTo {
        assert(!action.focusDown)
        assert(!action.focusUp)
        assert(!action.focusPrimary)
        assert(!action.sink)
        assert(!action.swapDown)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.swapWorkspaces)
        assert(!action.nextLayout)
        assert(action.view == nil)
        assert(action.focusOutput == 0)
        assert(action.moveToOutput == 0)
        assert(action.switchVt == 0)
        return .moveTo(tag: String(cString: tag))
    } else if action.moveToOutput != 0 {
        assert(!action.focusDown)
        assert(!action.focusUp)
        assert(!action.focusPrimary)
        assert(!action.sink)
        assert(!action.swapDown)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.swapWorkspaces)
        assert(!action.nextLayout)
        assert(action.focusOutput == 0)
        assert(action.switchVt == 0)
        return .moveToOutput(n: action.moveToOutput)
    } else if let tag = action.view {
        assert(!action.focusDown)
        assert(!action.focusUp)
        assert(!action.focusPrimary)
        assert(!action.sink)
        assert(!action.swapDown)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.swapWorkspaces)
        assert(!action.nextLayout)
        assert(action.focusOutput == 0)
        assert(action.switchVt == 0)
        return .view(tag: String(cString: tag))
    } else if action.close {
        assert(!action.configReload)
        assert(!action.focusUp)
        assert(!action.focusPrimary)
        assert(!action.sink)
        assert(!action.swapDown)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.nextLayout)
        assert(action.switchVt == 0)
        return .close
    } else if action.configReload {
        assert(!action.focusUp)
        assert(!action.focusPrimary)
        assert(!action.sink)
        assert(!action.swapDown)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.nextLayout)
        assert(action.switchVt == 0)
        return .configReload
    } else if action.focusDown {
        assert(!action.focusUp)
        assert(!action.focusPrimary)
        assert(!action.sink)
        assert(!action.swapDown)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.swapWorkspaces)
        assert(!action.nextLayout)
        assert(action.focusOutput == 0)
        assert(action.switchVt == 0)
        return .focusDown
    }  else if action.focusUp {
        assert(!action.focusPrimary)
        assert(!action.sink)
        assert(!action.swapDown)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.swapWorkspaces)
        assert(!action.nextLayout)
        assert(action.focusOutput == 0)
        assert(action.switchVt == 0)
        return .focusUp
    } else if action.focusPrimary {
        assert(!action.sink)
        assert(!action.swapDown)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.swapWorkspaces)
        assert(!action.nextLayout)
        assert(action.focusOutput == 0)
        assert(action.switchVt == 0)
        return .focusPrimary
    } else if action.focusOutput != 0 {
        assert(!action.nextLayout)
        assert(!action.sink)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.swapWorkspaces)
        assert(action.switchVt == 0)
        return .focusOutput(n: action.focusOutput)
    }  else if action.swapDown {
        assert(!action.nextLayout)
        assert(!action.sink)
        assert(!action.swapUp)
        assert(!action.swapPrimary)
        assert(!action.swapWorkspaces)
        assert(action.switchVt == 0)
        return .swapDown
    }  else if action.swapUp {
        assert(!action.nextLayout)
        assert(!action.sink)
        assert(!action.swapPrimary)
        assert(!action.swapWorkspaces)
        assert(action.switchVt == 0)
        return .swapUp
    }  else if action.swapPrimary {
        assert(!action.sink)
        assert(!action.swapWorkspaces)
        assert(action.switchVt == 0)
        return .swapPrimary
    } else if action.sink {
        assert(!action.swapWorkspaces)
        assert(action.switchVt == 0)
        return .sink
    }  else if action.swapWorkspaces {
        assert(action.switchVt == 0)
        return .swapWorkspaces
    } else if action.nextLayout {
        assert(action.switchVt == 0)
        return .nextLayout
    } else {
        assert(action.switchVt != 0)
        return .switchVt(n: action.switchVt)
    }
}

private func toButtonAction(_ action: inout AwcButtonAction) -> ButtonAction {
    if action.move {
        assert(!action.resize)
        return .move
    } else {
        return .resize
    }
}

private func toButton(_ button: UInt32) -> UInt32 {
    switch button {
    case 1: return UInt32(BTN_LEFT)
    case 3: return UInt32(BTN_RIGHT)
    default: fatalError("Unknown button: \(button)")
    }
}

func runAutostart() {
    let autostartCPath = awcAutostartPath()
    defer {
        free(autostartCPath)
    }

    let autostartPath = String(cString: autostartCPath!)
    if FileManager.default.isExecutableFile(atPath: autostartPath) {
        executeCommand(autostartPath)
    }
}
