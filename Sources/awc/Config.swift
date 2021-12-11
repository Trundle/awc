import Foundation

import awc_config
import Libawc
import Wlroots

extension AwcColor {
    func toFloatRgba() -> float_rgba {
        float_rgba(r: Float(self.r) / 255.0, g: Float(self.g) / 255.0, b: Float(self.b) / 255.0, a: Float(self.a) / 255.0)
    }
}


public enum Action {
    /// Close focused surface
    case close
    case configReload
    case execute(cmd: String)
    /// Expand the main area
    case expand
    /// Move focus to next surface
    case focusDown
    /// Move focus to previous surface
    case focusUp
    /// Focus primary window
    case focusPrimary
    /// Focus output n
    case focusOutput(n: UInt8)
    /// Bring the workspace with the given tag to the current output
    case greedyView(tag: String)
    /// Swap the focused surface with the next surface
    case swapDown
    /// Swap the focused surface with the previous surface
    case swapUp
    /// Swap the focused surface and the primary surface
    case swapPrimary
    /// Move focused surface to workspace with the given tag
    case moveTo(tag: String)
    /// Move focused surface to output n
    case moveToOutput(n: UInt8)
    case nextLayout
    /// Reset the layouts on the current workspace to default
    case resetLayouts
    /// Shrink the main area
    case shrink
    /// Push focused surface back into tiling
    case sink
    /// Swap workspaces on primary and secondary output
    case swapWorkspaces
    /// Swaps the tags of the currently focused workspace and the workspace with the given tag
    case swapWorkspaceTagWith(tag: String)
    case switchVt(n: UInt8)
    /// Switch to the workspace with the given tag
    case view(tag: String)
}

public enum ButtonAction {
    case move
    case resize
    case resizeByFrame
}

enum Key: Hashable {
    case code(code: UInt32)
    case sym(sym: xkb_keysym_t)
}

enum KeyboardType {
    case builtin
    case external
}

enum WindowSelection {
    case focused
    case underCursor
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
    let path: String?
    let borderWidth: UInt32
    let colors: AwcColorsConfig
    let font: String
    let modifier: KeyModifiers
    let outputConfigs: [String: (Int32, Int32, Float)]
    let layout: AnyLayout<Surface, OutputDetails>
    let workspaces: [String]
    private let displayErrorCmd: String
    private let buttonBindings: [ButtonActionKey: (ButtonAction, WindowSelection)]
    private let keyBindings: [KeyActionKey: Action]
    private let keyboardConfigs: [(KeyboardType, String)]

    fileprivate init(
        path: String?,
        borderWidth: UInt32,
        colors: AwcColorsConfig,
        displayErrorCmd: String,
        font: String,
        modifier: KeyModifiers,
        buttonBindings: [ButtonActionKey: (ButtonAction, WindowSelection)],
        keyBindings: [KeyActionKey: Action],
        keyboardConfigs: [(KeyboardType, String)],
        outputConfigs: [String: (Int32, Int32, Float)],
        layout: AnyLayout<Surface, OutputDetails>,
        workspaces: [String]
    ) {
        self.path = path
        self.borderWidth = borderWidth
        self.colors = colors
        self.displayErrorCmd = displayErrorCmd
        self.font = font
        self.modifier = modifier
        self.buttonBindings = buttonBindings
        self.keyBindings = keyBindings
        self.keyboardConfigs = keyboardConfigs
        self.outputConfigs = outputConfigs
        self.layout = layout
        self.workspaces = workspaces
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

    func findButtonBinding(modifiers: KeyModifiers, button: UInt32) -> (ButtonAction, WindowSelection)? {
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

func loadConfig(path: String?) -> Config? {
    var config = AwcConfig()

    if let error = awc_config_load(path, &config) {
        print("[FATAL] Could not load config: \(String(cString: error))")
        awc_config_str_free(error)
        return nil
    }
    defer {
        awc_config_free(&config)
    }

    var buttonBindings: [ButtonActionKey: (ButtonAction, WindowSelection)] = [:]
    for i in 0..<config.number_of_button_bindings {
        let actionKey = ButtonActionKey(
            modifiers: toKeyModifiers(
              config.button_bindings[i].mods,
              config.button_bindings[i].number_of_mods),
            button: toButton(config.button_bindings[i].button)
        )
        buttonBindings[actionKey] = toButtonAction(config.button_bindings[i].action, config.button_bindings[i].window)
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

    var workspaces: [String] = []
    for i in 0..<config.number_of_workspaces {
        workspaces.append(String(cString: config.workspaces[i]!))
    }

    guard let layout: AnyLayout<Surface, OutputDetails> = try?
        buildLayout(config.layout, config.number_of_layout_ops)
    else {
        print("[ERROR] Invalid layout! Please use buildLayout")
        return nil
    }

    return Config(
        path: path,
        borderWidth: config.border_width,
        colors: config.colors,
        displayErrorCmd: String(cString: config.display_error_cmd),
        font: String(cString: config.font),
        modifier: toKeyModifiers(config.modifier),
        buttonBindings: buttonBindings,
        keyBindings: keyBindings,
        keyboardConfigs: keyboardConfigs,
        outputConfigs: outputConfigs,
        layout: layout,
        workspaces: workspaces
    )
}

private func toKeyModifiers(_ mods: UnsafePointer<AwcModifier>?, _ numberOfMods: Int) -> KeyModifiers {
    var result = KeyModifiers()
    for i in 0..<numberOfMods {
        let mod = mods![i]
        result.insert(toKeyModifiers(mod))
    }
    return result
}

private func toKeyModifiers(_ mod: AwcModifier) -> KeyModifiers {
    if mod == Alt {
        return .alt
    } else if mod == Ctrl {
        return .ctrl
    } else if mod == Logo {
        return .logo
    } else if mod == Mod5 {
        return .mod5
    } else if mod == Shift {
        return .shift
    }
    fatalError("Unknown modifier: \(mod)")
}

private func assertExactlyOneAction(_ action: AwcAction) {
    let noArgAction =
        [ action.close
        , action.config_reload
        , action.expand
        , action.focus_down
        , action.focus_up
        , action.focus_primary
        , action.reset_layouts
        , action.shrink
        , action.sink
        , action.swap_down
        , action.swap_up
        , action.swap_primary
        , action.swap_workspaces
        , action.next_layout
        ].reduce(false, { assert(!$0 || !$1); return $0 || $1 })

    let numArgAction =
        [ action.focus_output
        , action.move_to_output
        , action.switch_vt
        ].reduce(UInt8(0), { assert($0 == 0 || $1 == 0); return $0 + $1 })

    let stringArgAction: UnsafePointer<CChar>? =
        [ action.execute
        , action.greedy_view
        , action.move_to
        , action.swap_workspace_tag_with
        , action.view
        ].reduce(nil, { assert($0 == nil || $1 == nil); return $0 ?? $1 })

    assert(
        [ noArgAction
        , numArgAction != 0
        , stringArgAction != nil
        ].reduce(false, { assert(!$0 || !$1); return $0 || $1 })
    )
}

private func toAction(_ action: AwcAction) -> Action {
    assertExactlyOneAction(action)
    if let execute = action.execute {
        return .execute(cmd: String(cString: execute))
    } else if action.expand {
        return .expand
    } else if let tag = action.move_to {
        return .moveTo(tag: String(cString: tag))
    } else if action.move_to_output != 0 {
        return .moveToOutput(n: action.move_to_output)
    } else if let tag = action.view {
        return .view(tag: String(cString: tag))
    } else if action.close {
        return .close
    } else if action.config_reload {
        return .configReload
    } else if action.focus_down {
        return .focusDown
    }  else if action.focus_up {
        return .focusUp
    } else if action.focus_primary {
        return .focusPrimary
    } else if action.focus_output != 0 {
        return .focusOutput(n: action.focus_output)
    } else if let tag = action.greedy_view {
        return .greedyView(tag: String(cString: tag))
    } else if action.reset_layouts {
        return .resetLayouts
    }  else if action.swap_down {
        return .swapDown
    }  else if action.swap_up {
        return .swapUp
    }  else if action.swap_primary {
        return .swapPrimary
    } else if action.shrink {
        return .shrink
    } else if action.sink {
        return .sink
    }  else if action.swap_workspaces {
        return .swapWorkspaces
    } else if let tag = action.swap_workspace_tag_with {
        return .swapWorkspaceTagWith(tag: String(cString: tag))
    } else if action.next_layout {
        return .nextLayout
    } else {
        return .switchVt(n: action.switch_vt)
    }
}

private func toButtonAction(_ action: AwcButtonAction, _ window: AwcWindowSelection) -> (ButtonAction, WindowSelection)
{
    let selection: WindowSelection = window == Focused ? .focused : .underCursor
    if action == Move {
        return (.move, selection)
    } else if action == Resize {
        return (.resize, selection)
    } else if action == ResizeByFrame {
        return (.resizeByFrame, selection)
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
