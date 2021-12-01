extern crate xdg;

use libc::size_t;
use serde::Deserialize;
use std::env;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

// Intermediate structures

#[derive(Debug, Deserialize)]
enum Action {
    Close,
    ConfigReload,
    Execute(String),
    Expand,
    FocusDown,
    FocusUp,
    FocusOutput(u8),
    FocusPrimary,
    GreedyView(String),
    MoveTo(String),
    MoveToOutput(u8),
    ResetLayouts,
    Shrink,
    Sink,
    SwapDown,
    SwapUp,
    SwapPrimary,
    SwitchVT(u8),
    NextLayout,
    SwapWorkspaces,
    SwapWorkspaceTagWith(String),
    View(String),
}

impl Action {
    fn to_awc(&self) -> Result<AwcAction, String> {
        let mut action = AwcAction {
            execute: std::ptr::null(),
            expand: false,
            close: false,
            config_reload: false,
            focus_down: false,
            focus_up: false,
            focus_primary: false,
            focus_output: 0,
            greedy_view: std::ptr::null(),
            shrink: false,
            sink: false,
            swap_down: false,
            swap_up: false,
            swap_primary: false,
            swap_workspaces: false,
            swap_workspace_tag_with: std::ptr::null(),
            next_layout: false,
            reset_layouts: false,
            move_to: std::ptr::null(),
            move_to_output: 0,
            switch_vt: 0,
            view: std::ptr::null(),
        };
        match self {
            Action::Close => action.close = true,
            Action::ConfigReload => action.config_reload = true,
            Action::Execute(cmd) => action.execute = str_to_c_char(&cmd, "execute command")?,
            Action::Expand => action.expand = true,
            Action::FocusDown => action.focus_down = true,
            Action::FocusUp => action.focus_up = true,
            Action::FocusOutput(output) => action.focus_output = *output,
            Action::FocusPrimary => action.focus_primary = true,
            Action::GreedyView(ws) => action.greedy_view = str_to_c_char(&ws, "greedyView target")?,
            Action::MoveTo(ws) => action.move_to = str_to_c_char(&ws, "move target")?,
            Action::MoveToOutput(output) => action.move_to_output = *output,
            Action::ResetLayouts => action.reset_layouts = true,
            Action::Shrink => action.shrink = true,
            Action::Sink => action.sink = true,
            Action::SwapDown => action.swap_down = true,
            Action::SwapUp => action.swap_up = true,
            Action::SwapPrimary => action.swap_primary = true,
            Action::SwitchVT(vt) => action.switch_vt = *vt,
            Action::NextLayout => action.next_layout = true,
            Action::SwapWorkspaces => action.swap_workspaces = true,
            Action::SwapWorkspaceTagWith(ws) =>
                action.swap_workspace_tag_with = str_to_c_char(&ws, "swap workspace tag")?,
            Action::View(ws) => action.view = str_to_c_char(&ws, "view target")?,
        }
        Ok(action)
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ButtonBinding {
    mods: Vec<AwcModifier>,
    button: AwcButton,
    action: AwcButtonAction,
    window: AwcWindowSelection,
}

impl ButtonBinding {
    fn to_awc(&self) -> AwcButtonBinding {
        let (mods, number_of_mods) = vec_into_raw(self.mods.clone());
        AwcButtonBinding {
            mods,
            number_of_mods,
            button: self.button,
            action: self.action,
            window: self.window,
        }
    }
}

#[derive(Debug, Deserialize)]
enum Key {
    Code(u32),
    Sym(String),
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct KeyBinding {
    mods: Vec<AwcModifier>,
    key: Key,
    action: Action,
}

impl KeyBinding {
    fn to_awc(&self) -> Result<AwcKeyBinding, String> {
        let (mods, number_of_mods) = vec_into_raw(self.mods.clone());
        let (code, sym) = match &self.key {
            Key::Code(code) => (*code, std::ptr::null()),
            Key::Sym(sym) => (0, str_to_c_char(&sym, "Key symbol")?),
        };
        Ok(AwcKeyBinding {
            action: self.action.to_awc()?,
            mods,
            number_of_mods,
            code,
            sym,
        })
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct KeyboardConfig {
    layout: String,
    type_: AwcKeyboardType,
}

impl KeyboardConfig {
    fn to_awc(&self) -> Result<AwcKeyboardConfig, String> {
        Ok(AwcKeyboardConfig {
            layout: str_to_c_char(&self.layout, "keyboard layout")?,
            type_: self.type_,
        })
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct OutputConfig {
    name: String,
    x: i32,
    y: i32,
    scale: f32,
}

impl OutputConfig {
    fn to_awc(&self) -> Result<AwcOutputConfig, String> {
        Ok(AwcOutputConfig {
            name: str_to_c_char(&self.name, "output name")?,
            x: self.x,
            y: self.y,
            scale: self.scale,
        })
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    border_width: u32,
    active_border_color: AwcColor,
    inactive_border_color: AwcColor,
    font: String,
    modifier: AwcModifier,
    display_error_cmd: String,
    button_bindings: Vec<ButtonBinding>,
    key_bindings: Vec<KeyBinding>,
    keyboards: Vec<KeyboardConfig>,
    layout: Vec<AwcLayoutOp>,
    outputs: Vec<OutputConfig>,
    output_hud: AwcOutputHudConfig,
    workspaces: Vec<String>,
}

impl Config {
    unsafe fn copy_to(self, target: *mut AwcConfig) -> Result<(), String> {
        let converted_button_bindings = self
            .button_bindings
            .iter()
            .map(|b| b.to_awc())
            .collect::<Vec<AwcButtonBinding>>();
        let (button_bindings, number_of_button_bindings) = vec_into_raw(converted_button_bindings);
        (*target).button_bindings = button_bindings;
        (*target).number_of_button_bindings = number_of_button_bindings;

        let converted_key_bindings = self
            .key_bindings
            .iter()
            .map(|b| b.to_awc())
            .collect::<Result<Vec<AwcKeyBinding>, String>>()?;
        let (key_bindings, number_of_key_bindings) = vec_into_raw(converted_key_bindings);
        (*target).key_bindings = key_bindings;
        (*target).number_of_key_bindings = number_of_key_bindings;

        let converted_keyboards = self
            .keyboards
            .iter()
            .map(|k| k.to_awc())
            .collect::<Result<Vec<AwcKeyboardConfig>, String>>()?;
        let (keyboards, number_of_keyboards) = vec_into_raw(converted_keyboards);
        (*target).keyboards = keyboards;
        (*target).number_of_keyboards = number_of_keyboards;

        let (layout, number_of_layout_ops) = vec_into_raw(self.layout);
        (*target).layout = layout;
        (*target).number_of_layout_ops = number_of_layout_ops;

        let converted_outputs = self
            .outputs
            .iter()
            .map(|o| o.to_awc())
            .collect::<Result<Vec<AwcOutputConfig>, String>>()?;
        let (outputs, number_of_outputs) = vec_into_raw(converted_outputs);
        (*target).outputs = outputs;
        (*target).number_of_outputs = number_of_outputs;

        let converted_workspaces = self
            .workspaces
            .iter()
            .map(|w| str_to_c_char(&w, "workspace"))
            .collect::<Result<Vec<*const c_char>, String>>()?;
        let (workspaces, number_of_workspaces) = vec_into_raw(converted_workspaces);
        (*target).workspaces = workspaces;
        (*target).number_of_workspaces = number_of_workspaces;

        (*target).display_error_cmd = str_to_c_char(&self.display_error_cmd, "displayErrorCmd")?;
        (*target).font = str_to_c_char(&self.font, "font")?;
        (*target).modifier = self.modifier;
        (*target).border_width = self.border_width;
        (*target).active_border_color = self.active_border_color;
        (*target).inactive_border_color = self.inactive_border_color;
        (*target).output_hud = self.output_hud;

        Ok(())
    }
}

// ### Public structures ###

#[repr(C)]
pub struct AwcAction {
    execute: *const c_char,
    expand: bool,
    close: bool,
    config_reload: bool,
    focus_down: bool,
    focus_up: bool,
    focus_primary: bool,
    focus_output: u8,
    greedy_view: *const c_char,
    shrink: bool,
    sink: bool,
    swap_down: bool,
    swap_up: bool,
    swap_primary: bool,
    swap_workspaces: bool,
    swap_workspace_tag_with: *const c_char,
    next_layout: bool,
    reset_layouts: bool,
    move_to: *const c_char,
    move_to_output: u8,
    switch_vt: u8,
    view: *const c_char,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[repr(C)]
pub struct AwcColor {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[repr(C)]
pub enum AwcModifier {
    Alt,
    Ctrl,
    Logo,
    Mod5,
    Shift,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[repr(C)]
pub enum AwcButton {
    Left,
    Right,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[repr(C)]
pub enum AwcButtonAction {
    Move,
    Resize,
    ResizeByFrame,
}

#[repr(C)]
pub struct AwcButtonBinding {
    mods: *const AwcModifier,
    number_of_mods: size_t,
    button: AwcButton,
    action: AwcButtonAction,
    window: AwcWindowSelection,
}

#[repr(C)]
pub struct AwcKeyBinding {
    action: AwcAction,
    mods: *const AwcModifier,
    number_of_mods: size_t,
    code: u32,
    sym: *const c_char,
}

#[repr(C)]
pub struct AwcKeyboardConfig {
    layout: *const c_char,
    type_: AwcKeyboardType,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[repr(C)]
pub enum AwcKeyboardType {
    Builtin,
    External,
}

#[repr(C)]
pub struct AwcOutputConfig {
    name: *const c_char,
    x: i32,
    y: i32,
    scale: f32,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
#[repr(C)]
pub struct AwcOutputHudConfig {
    active_background_color: AwcColor,
    active_foreground_color: AwcColor,
    inactive_background_color: AwcColor,
    inactive_foreground_color: AwcColor,
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[repr(C)]
pub enum AwcDirection {
    Horizontal,
    Vertical
}

/// cbindgen:prefix-with-name
#[derive(Clone, Copy, Debug, Deserialize)]
#[repr(C)]
pub enum AwcLayoutOp {
    Choose,
    Full,
    TwoPane { split: f64, delta: f64 },
    Reflected(AwcDirection),
    Rotated,
    Push    
}

#[derive(Clone, Copy, Debug, Deserialize)]
#[repr(C)]
pub enum AwcWindowSelection {
    Focused,
    UnderCursor,
}

#[repr(C)]
pub struct AwcConfig {
    active_border_color: AwcColor,
    inactive_border_color: AwcColor,
    border_width: u32,
    display_error_cmd: *const c_char,
    font: *const c_char,
    modifier: AwcModifier,
    output_hud: AwcOutputHudConfig,

    button_bindings: *const AwcButtonBinding,
    number_of_button_bindings: size_t,

    key_bindings: *const AwcKeyBinding,
    number_of_key_bindings: size_t,

    keyboards: *const AwcKeyboardConfig,
    number_of_keyboards: size_t,

    layout: *const AwcLayoutOp,
    number_of_layout_ops: size_t,

    outputs: *const AwcOutputConfig,
    number_of_outputs: size_t,

    workspaces: *const *const c_char,
    number_of_workspaces: size_t,
}

// ### Helpers ###

fn str_to_c_char(value: &str, descr: &str) -> Result<*const c_char, String> {
    CString::new(value)
        .map_err(|_| format!("{} must not contain 0 byte", descr))
        .map(|s| s.into_raw() as *const c_char)
}

fn vec_into_raw<T>(vec: Vec<T>) -> (*const T, usize) {
    let boxed_slice = vec.into_boxed_slice();
    let ptr = boxed_slice.as_ptr();
    let len = boxed_slice.len();
    std::mem::forget(boxed_slice);
    (ptr, len)
}

fn load_config(path: &str, result: *mut AwcConfig) -> Result<(), String> {
    let config: Config = serde_dhall::from_file(path)
        .parse()
        .map_err(|e| e.to_string())?;
    unsafe {
        config.copy_to(result).map_err(|e| {
            awc_config_free(result);
            e
        })
    }
}

// ### Public API ###

/// # Safety
///
/// `path` must point to a NULL-terminated string. The return value must be
/// freed with `awc_config_str_free` after use. `result` must be freed with
/// `awc_config_free` after use and the referenced `AwcConfig` structure must
/// not be modified between this function's return and the free call.
#[no_mangle]
pub unsafe extern "C" fn awc_config_load(
    path: *const c_char,
    result: *mut AwcConfig,
) -> *const c_char {
    let path_str = if path != std::ptr::null() {
        CStr::from_ptr(path).to_string_lossy().into_owned()
    } else {
        let config_path = xdg::BaseDirectories::with_prefix("awc")
            .ok()
            .and_then(|xdg_dirs| xdg_dirs.find_config_file("config.dhall"))
            .and_then(|p| p.to_str().map(|p| p.to_string()));
        match config_path {
            Some(path) => path,
            None => {
                return CString::new("no config file or non-utf8 path")
                    .map(|p| p.into_raw() as *const c_char)
                    .unwrap()
            }
        }
    };

    let types = include_str!("../Dhall/Types.dhall");
    env::set_var("AWC_TYPES", &types);

    let result = load_config(&path_str, result);
    env::remove_var("AWC_TYPES");
    match result {
        Err(desc) => CString::new(desc)
            .map(|p| p.into_raw() as *const c_char)
            // Error messages shouldn't contain any 0 bytes
            .unwrap(),
        Ok(_) => std::ptr::null(),
    }
}

/// # Safety
///
/// This function only takes values that have been passed to a successful call
/// of `awc_config_load` before.
#[no_mangle]
pub unsafe extern "C" fn awc_config_free(config: *mut AwcConfig) {
    Box::from_raw(std::slice::from_raw_parts_mut(
        (*config).button_bindings as *mut AwcButtonBinding,
        (*config).number_of_button_bindings,
    ));

    Box::from_raw(std::slice::from_raw_parts_mut(
        (*config).key_bindings as *mut AwcKeyBinding,
        (*config).number_of_key_bindings,
    ))
    .iter()
    .for_each(|binding| {
        awc_config_str_free(binding.action.execute);
        awc_config_str_free(binding.action.move_to);
        awc_config_str_free(binding.action.view);
    });

    Box::from_raw(std::slice::from_raw_parts_mut(
        (*config).keyboards as *mut AwcKeyboardConfig,
        (*config).number_of_keyboards,
    ))
    .iter()
    .for_each(|keyboard| awc_config_str_free(keyboard.layout));

    Box::from_raw(std::slice::from_raw_parts_mut(
        (*config).layout as *mut AwcLayoutOp,
        (*config).number_of_layout_ops,
    ));

    Box::from_raw(std::slice::from_raw_parts_mut(
        (*config).outputs as *mut AwcOutputConfig,
        (*config).number_of_outputs,
    ))
    .iter()
    .for_each(|output| awc_config_str_free(output.name));

    awc_config_str_free((*config).display_error_cmd);
}

#[no_mangle]
pub extern "C" fn awc_config_autostart_path() -> *const c_char {
    xdg::BaseDirectories::with_prefix("awc")
        .ok()
        .and_then(|xdg_dirs| xdg_dirs.find_config_file("autostart"))
        .and_then(|p| p.to_str().and_then(|s| CString::new(s).ok()))
        .map(|p| p.into_raw() as *const c_char)
        .unwrap_or_else(std::ptr::null)
}

/// # Safety
///
/// This function is only allowed to be called with return values from some
/// `aws_config_*` call.
#[no_mangle]
pub unsafe extern "C" fn awc_config_str_free(str: *const c_char) {
    if !str.is_null() {
        CString::from_raw(str as *mut c_char);
    }
}
