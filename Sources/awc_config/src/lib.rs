extern crate xdg;

use libc::size_t;
use serde::Deserialize;
use std::env;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

// Intermediate structures

#[derive(Deserialize)]
enum Action {
    Close,
    ConfigReload,
    Execute(String),
    FocusDown,
    FocusUp,
    FocusOutput(u8),
    FocusPrimary,
    MoveTo(String),
    MoveToOutput(u8),
    Sink,
    SwapDown,
    SwapUp,
    SwapPrimary,
    SwitchVT(u8),
    NextLayout,
    SwapWorkspaces,
    View(String),
}

impl Action {
    fn to_awc(&self) -> Result<AwcAction, String> {
        let mut action = AwcAction {
            execute: std::ptr::null(),
            close: false,
            config_reload: false,
            focus_down: false,
            focus_up: false,
            focus_primary: false,
            focus_output: 0,
            sink: false,
            swap_down: false,
            swap_up: false,
            swap_primary: false,
            swap_workspaces: false,
            next_layout: false,
            move_to: std::ptr::null(),
            move_to_output: 0,
            switch_vt: 0,
            view: std::ptr::null(),
        };
        match self {
            Action::Close => action.close = true,
            Action::ConfigReload => action.config_reload = true,
            Action::Execute(cmd) => action.execute = str_to_c_char(&cmd, "execute command")?,
            Action::FocusDown => action.focus_down = true,
            Action::FocusUp => action.focus_up = true,
            Action::FocusOutput(output) => action.focus_output = *output,
            Action::FocusPrimary => action.focus_primary = true,
            Action::MoveTo(ws) => action.move_to = str_to_c_char(&ws, "move target")?,
            Action::MoveToOutput(output) => action.move_to_output = *output,
            Action::Sink => action.sink = true,
            Action::SwapDown => action.swap_down = true,
            Action::SwapUp => action.swap_up = true,
            Action::SwapPrimary => action.swap_primary = true,
            Action::SwitchVT(vt) => action.switch_vt = *vt,
            Action::NextLayout => action.next_layout = true,
            Action::SwapWorkspaces => action.swap_workspaces = true,
            Action::View(ws) => action.view = str_to_c_char(&ws, "view target")?,
        }
        Ok(action)
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ButtonBinding {
    mods: Vec<AwcModifier>,
    button: AwcButton,
    action: AwcButtonAction,
}

impl ButtonBinding {
    fn to_awc(&self) -> AwcButtonBinding {
        let (mods, number_of_mods) = vec_into_raw(self.mods.clone());
        AwcButtonBinding {
            mods,
            number_of_mods,
            button: self.button,
            action: self.action,
        }
    }
}

#[derive(Deserialize)]
enum Key {
    Code(u32),
    Sym(String),
}

#[derive(Deserialize)]
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

#[derive(Deserialize)]
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

#[derive(Deserialize)]
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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    border_width: u32,
    active_border_color: AwcColor,
    inactive_border_color: AwcColor,
    display_error_cmd: String,
    button_bindings: Vec<ButtonBinding>,
    key_bindings: Vec<KeyBinding>,
    keyboards: Vec<KeyboardConfig>,
    outputs: Vec<OutputConfig>,
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

        let converted_outputs = self
            .outputs
            .iter()
            .map(|o| o.to_awc())
            .collect::<Result<Vec<AwcOutputConfig>, String>>()?;
        let (outputs, number_of_outputs) = vec_into_raw(converted_outputs);
        (*target).outputs = outputs;
        (*target).number_of_outputs = number_of_outputs;

        (*target).display_error_cmd = str_to_c_char(&self.display_error_cmd, "displayErrorCmd")?;
        (*target).border_width = self.border_width;
        (*target).active_border_color = self.active_border_color;
        (*target).inactive_border_color = self.inactive_border_color;

        Ok(())
    }
}

// ### Public structures ###

#[repr(C)]
pub struct AwcAction {
    execute: *const c_char,
    close: bool,
    config_reload: bool,
    focus_down: bool,
    focus_up: bool,
    focus_primary: bool,
    focus_output: u8,
    sink: bool,
    swap_down: bool,
    swap_up: bool,
    swap_primary: bool,
    swap_workspaces: bool,
    next_layout: bool,
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

#[derive(Clone, Copy, Deserialize)]
#[repr(C)]
pub enum AwcModifier {
    Alt,
    Ctrl,
    Logo,
    Shift,
}

#[derive(Clone, Copy, Deserialize)]
#[repr(C)]
pub enum AwcButton {
    Left,
    Right,
}

#[derive(Clone, Copy, Deserialize)]
#[repr(C)]
pub enum AwcButtonAction {
    Move,
    Resize,
}

#[repr(C)]
pub struct AwcButtonBinding {
    mods: *const AwcModifier,
    number_of_mods: size_t,
    button: AwcButton,
    action: AwcButtonAction,
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

#[derive(Clone, Copy, Deserialize)]
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

#[repr(C)]
pub struct AwcConfig {
    active_border_color: AwcColor,
    inactive_border_color: AwcColor,
    border_width: u32,
    display_error_cmd: *const c_char,

    button_bindings: *const AwcButtonBinding,
    number_of_button_bindings: size_t,

    key_bindings: *const AwcKeyBinding,
    number_of_key_bindings: size_t,

    keyboards: *const AwcKeyboardConfig,
    number_of_keyboards: size_t,

    outputs: *const AwcOutputConfig,
    number_of_outputs: size_t,
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

    match load_config(&path_str, result) {
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
