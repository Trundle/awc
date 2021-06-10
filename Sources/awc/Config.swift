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

enum KeyboardType {
    case builtin
    case external
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
    private let displayErrorCmd: String
    private let buttonBindings: [ButtonActionKey: ButtonAction]
    private let keyBindings: [KeyActionKey: Action]
    private let keyboardConfigs: [(KeyboardType, String)]

    fileprivate init(
        borderWidth: UInt32,
        activeBorderColor: float_rgba,
        inactiveBorderColor: float_rgba,
        displayErrorCmd: String,
        buttonBindings: [ButtonActionKey: ButtonAction],
        keyBindings: [KeyActionKey: Action],
        keyboardConfigs: [(KeyboardType, String)],
        outputConfigs: [String: (Int32, Int32, Float)]
    ) {
        self.borderWidth = borderWidth
        self.activeBorderColor = activeBorderColor
        self.inactiveBorderColor = inactiveBorderColor
        self.displayErrorCmd = displayErrorCmd
        self.buttonBindings = buttonBindings
        self.keyBindings = keyBindings
        self.keyboardConfigs = keyboardConfigs
        self.outputConfigs = outputConfigs
    }

    func configureKeyboard(vendor: UInt32) -> String {
        for config in self.keyboardConfigs {
            if config.0 == .builtin && vendor <= 1 {
                return config.1
            } else if config.0 == .external && vendor > 1 {
                return config.1
            }
        }
        return "de(nodeadkeys)"
    }

    func generateErrorDisplayCmd(msg: String) -> String {
        // XXX shell escape
        return "\(displayErrorCmd) \"\(msg)\""
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

    if let error = awc_config_load(nil, &config) {
        print("[FATAL] Could not load config: \(String(cString: error))")
        awc_config_str_free(error)
        return nil
    }
    defer {
        awc_config_free(&config)
    }

    var buttonBindings: [ButtonActionKey: ButtonAction] = [:]
    for i in 0..<config.number_of_button_bindings {
        let actionKey = ButtonActionKey(
            modifiers: toKeyModifiers(
              config.button_bindings[i].mods,
              config.button_bindings[i].number_of_mods),
            button: toButton(config.button_bindings[i].button)
        )
        buttonBindings[actionKey] = toButtonAction(config.button_bindings[i].action)
    }

    var keyBindings: [KeyActionKey: Action] = [:]
    for i in 0..<config.number_of_key_bindings {
        let key: Key
        if let sym = config.key_bindings[i].sym {
            let keySym = xkb_keysym_from_name(sym, XKB_KEYSYM_NO_FLAGS)
            if keySym == 0 {
                print("[WARN] Unknown key symbol: \(String(cString: sym))")
                continue
            }
            key = Key.sym(sym: keySym)
        } else {
            assert(config.key_bindings[i].code != 0)
            key = Key.code(code: config.key_bindings[i].code)
        }
        let actionKey = KeyActionKey(
            modifiers: toKeyModifiers(
              config.key_bindings[i].mods,
              config.key_bindings[i].number_of_mods),
            key: key
        )
        keyBindings[actionKey] = toAction(config.key_bindings[i].action)
    }

    var keyboardConfigs: [(KeyboardType, String)] = []
    for i in 0..<config.number_of_keyboards {
        let type: KeyboardType
        if config.keyboards[i].type_ == Builtin {
            type = .builtin
        } else {
            type = .external
        }
        keyboardConfigs.append((type, String(cString: config.keyboards[i].layout)))
    }

    var outputConfigs: [String: (Int32, Int32, Float)] = [:]
    for i in 0..<config.number_of_outputs {
        let scale: Float = config.outputs[i].scale
        outputConfigs[String(cString: config.outputs[i].name)] =
            (config.outputs[i].x, config.outputs[i].y, scale)
    }

    return Config(
        borderWidth: config.border_width,
        activeBorderColor: config.active_border_color.toFloatRgba(),
        inactiveBorderColor: config.inactive_border_color.toFloatRgba(),
        displayErrorCmd: String(cString: config.display_error_cmd),
        buttonBindings: buttonBindings,
        keyBindings: keyBindings,
        keyboardConfigs: keyboardConfigs,
        outputConfigs: outputConfigs
    )
}

private func toKeyModifiers(_ mods: UnsafePointer<AwcModifier>?, _ numberOfMods: Int) -> KeyModifiers {
    var result = KeyModifiers()
    for i in 0..<numberOfMods {
        let mod = mods![i]
        if mod == Alt {
            result.insert(.alt)
        } else if mod == Ctrl {
            result.insert(.ctrl)
        } else if mod == Logo {
            result.insert(.logo)
        } else if mod == Shift {
            result.insert(.shift)
        }
    }
    return result
}

private func toAction(_ action: AwcAction) -> Action {
    if let execute = action.execute {
        assert(action.switch_vt == 0)
        assert(!action.focus_down)
        assert(!action.focus_up)
        assert(!action.focus_primary)
        assert(!action.sink)
        assert(!action.swap_down)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.swap_workspaces)
        assert(!action.next_layout)
        assert(action.move_to == nil)
        assert(action.view == nil)
        assert(action.focus_output == 0)
        assert(action.move_to_output == 0)
        assert(action.switch_vt == 0)
        return .execute(cmd: String(cString: execute))
    } else if let tag = action.move_to {
        assert(!action.focus_down)
        assert(!action.focus_up)
        assert(!action.focus_primary)
        assert(!action.sink)
        assert(!action.swap_down)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.swap_workspaces)
        assert(!action.next_layout)
        assert(action.view == nil)
        assert(action.focus_output == 0)
        assert(action.move_to_output == 0)
        assert(action.switch_vt == 0)
        return .moveTo(tag: String(cString: tag))
    } else if action.move_to_output != 0 {
        assert(!action.focus_down)
        assert(!action.focus_up)
        assert(!action.focus_primary)
        assert(!action.sink)
        assert(!action.swap_down)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.swap_workspaces)
        assert(!action.next_layout)
        assert(action.focus_output == 0)
        assert(action.switch_vt == 0)
        return .moveToOutput(n: action.move_to_output)
    } else if let tag = action.view {
        assert(!action.focus_down)
        assert(!action.focus_up)
        assert(!action.focus_primary)
        assert(!action.sink)
        assert(!action.swap_down)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.swap_workspaces)
        assert(!action.next_layout)
        assert(action.focus_output == 0)
        assert(action.switch_vt == 0)
        return .view(tag: String(cString: tag))
    } else if action.close {
        assert(!action.config_reload)
        assert(!action.focus_up)
        assert(!action.focus_primary)
        assert(!action.sink)
        assert(!action.swap_down)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.next_layout)
        assert(action.switch_vt == 0)
        return .close
    } else if action.config_reload {
        assert(!action.focus_up)
        assert(!action.focus_primary)
        assert(!action.sink)
        assert(!action.swap_down)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.next_layout)
        assert(action.switch_vt == 0)
        return .configReload
    } else if action.focus_down {
        assert(!action.focus_up)
        assert(!action.focus_primary)
        assert(!action.sink)
        assert(!action.swap_down)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.swap_workspaces)
        assert(!action.next_layout)
        assert(action.focus_output == 0)
        assert(action.switch_vt == 0)
        return .focusDown
    }  else if action.focus_up {
        assert(!action.focus_primary)
        assert(!action.sink)
        assert(!action.swap_down)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.swap_workspaces)
        assert(!action.next_layout)
        assert(action.focus_output == 0)
        assert(action.switch_vt == 0)
        return .focusUp
    } else if action.focus_primary {
        assert(!action.sink)
        assert(!action.swap_down)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.swap_workspaces)
        assert(!action.next_layout)
        assert(action.focus_output == 0)
        assert(action.switch_vt == 0)
        return .focusPrimary
    } else if action.focus_output != 0 {
        assert(!action.next_layout)
        assert(!action.sink)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.swap_workspaces)
        assert(action.switch_vt == 0)
        return .focusOutput(n: action.focus_output)
    }  else if action.swap_down {
        assert(!action.next_layout)
        assert(!action.sink)
        assert(!action.swap_up)
        assert(!action.swap_primary)
        assert(!action.swap_workspaces)
        assert(action.switch_vt == 0)
        return .swapDown
    }  else if action.swap_up {
        assert(!action.next_layout)
        assert(!action.sink)
        assert(!action.swap_primary)
        assert(!action.swap_workspaces)
        assert(action.switch_vt == 0)
        return .swapUp
    }  else if action.swap_primary {
        assert(!action.sink)
        assert(!action.swap_workspaces)
        assert(action.switch_vt == 0)
        return .swapPrimary
    } else if action.sink {
        assert(!action.swap_workspaces)
        assert(action.switch_vt == 0)
        return .sink
    }  else if action.swap_workspaces {
        assert(action.switch_vt == 0)
        return .swapWorkspaces
    } else if action.next_layout {
        assert(action.switch_vt == 0)
        return .nextLayout
    } else {
        assert(action.switch_vt != 0)
        return .switchVt(n: action.switch_vt)
    }
}

private func toButtonAction(_ action: AwcButtonAction) -> ButtonAction {
    if action == Move {
        return .move
    } else if action == Resize {
        return .resize
    } else {
        fatalError("Unknown button action: \(action)")
    }
}

private func toButton(_ button: AwcButton) -> UInt32 {
    if button ==  Left {
        return UInt32(BTN_LEFT)
    } else if button == Right {
        return UInt32(BTN_RIGHT)
    } else {
        fatalError("Unknown button: \(button)")
    }
}

func runAutostart() {
    let autostartCPath = awc_config_autostart_path()
    defer {
        awc_config_str_free(autostartCPath)
    }

    let autostartPath = String(cString: autostartCPath!)
    if FileManager.default.isExecutableFile(atPath: autostartPath) {
        executeCommand(autostartPath)
    }
}
