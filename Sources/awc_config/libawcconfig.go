package main

// The public C API

/*
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

struct AwcKeyboardConfig {
    char *Layout;
};

struct AwcOutputConfig {
   char *name;
   int x;
   int y;
   float scale;
};

struct AwcAction {
    char *execute;
    bool close;
    bool configReload;
    bool focusDown;
    bool focusUp;
    bool focusPrimary;
    uint8_t focusOutput;
    bool sink;
    bool swapDown;
    bool swapUp;
    bool swapPrimary;
    bool swapWorkspaces;
    bool nextLayout;
    char *moveTo;
    uint8_t moveToOutput;
    uint8_t switchVt;
    char *view;
};

struct AwcKeyBinding {
    struct AwcAction action;
    // Keep in sync with wlr_keyboard_modifier
    uint32_t mods;
    uint32_t code;
    char *sym;
};

struct AwcButtonAction {
   bool move;
   bool resize;
};

struct AwcButtonBinding {
   struct AwcButtonAction action;
   uint32_t mods;
   uint32_t button;
};

struct AwcColor {
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
};

struct AwcConfig {
    void *token;
    uint32_t borderWidth;
    struct AwcColor activeBorderColor;
    struct AwcColor inactiveBorderColor;
    struct AwcKeyBinding* keyBindings;
    size_t numberOfKeyBindings;
    struct AwcButtonBinding* buttonBindings;
    size_t numberOfButtonBindings;
    struct AwcOutputConfig *outputs;
    size_t numberOfOutputs;
};


typedef const char* const_char_p;
*/
import "C"

import (
	"bytes"
	"io"
	"os"
	"os/signal"
	"syscall"
	"text/template"
	"unsafe"

	"github.com/adrg/xdg"
	"github.com/philandstuff/dhall-golang/v5"
)


//go:generate go run Dhall/embed.go Dhall/Types.dhall
//go:generate go run Dhall/embed.go Dhall/Deunionize.dhall

// Structures used for unmarshalling

type KeyboardConfig struct {
	Layout string `dhall:"layout"`
}

type KeyBinding struct {
	Action struct {
		Execute *string `dhall:"execute"`
		Close bool `dhall:"close"`
		ConfigReload bool `dhall:"configReload"`
		FocusDown bool `dhall:"focusDown"`
		FocusUp bool `dhall:"focusUp"`
		FocusPrimary bool `dhall:"focusPrimary"`
		FocusOutput uint `dhall:"focusOutput"`
		Sink bool `dhall:"sink"`
		SwapDown bool `dhall:"swapDown"`
		SwapUp bool `dhall:"swapUp"`
		SwapPrimary bool `dhall:"swapPrimary"`
		SwapWorkspaces bool `dhall:"swapWorkspaces"`
		NextLayout bool `dhall:"nextLayout"`
		MoveTo *string `dhall:"moveTo"`
		MoveToOutput uint `dhall:"moveToOutput"`
		SwitchVT uint `dhall:"switchVt"`
		View *string `dhall:"view"`
	} `dhall:"action"`
	Modifiers int `dhall:"mods"`
	Key struct {
		Code uint `dhall:"code"`
		Sym *string `dhall:"sym"`
	} `dhall:"key"`
}

type ButtonBinding struct {
	Action struct {
		Move bool `dhall:"move"`
		Resize bool `dhall:"resize"`
	} `dhall:"action"`
	Modifiers int `dhall:"mods"`
	Button uint `dhall:"button"`
}

type Color struct {
	R uint `dhall:"r"`
	G uint `dhall:"g"`
	B uint `dhall:"b"`
	A uint `dhall:"a"`
}

func (color *Color)applyTo(target *C.struct_AwcColor) {
	target.r = C.uchar(color.R)
	target.g = C.uchar(color.G)
	target.b = C.uchar(color.B)
	target.a = C.uchar(color.A)
}


type Config struct {
	BorderWidth uint `dhall:"borderWidth"`
	ActiveBorderColor Color `dhall:"activeBorderColor"`
	InactiveBorderColor Color `dhall:"inactiveBorderColor"`
	ConfigureKeyboard func(uint) KeyboardConfig `dhall:"configureKeyboard"`
	Outputs []struct {
		Name string `dhall:"name"`
		X int `dhall:"x"`
		Y int `dhall:"y"`
		Scale float64 `dhall:"scale"`
	} `dhall:"outputs"`
	ButtonBindings []ButtonBinding `dhall:"buttonBindings"`
	KeyBindings []KeyBinding `dhall:"keyBindings"`
	ErrorDisplay func(string) string `dhall:"errorDisplay"`
}


// dhall-goland doesn't support unmarshalling unions, hence the loaded config
// need to be de-unionized prior to unmarshalling. This is done in dhall using
// the following converter.

var loaderTemplate = `
let Types = ({{ .Types }})
let Config/deunionize = ({{ .Deunionize }})

in  Config/deunionize ({{ .ConfigPath  }} : Types.Config.Type)
`


var sigUsr1HandlerInstalled = false
var configs = make(map[unsafe.Pointer]Config)

func installSigUsr1Handler() {
	if !sigUsr1HandlerInstalled {
		// Go installs a SIGUSR1 handler, but XWayland uses SIGUSR1 to
		// signal that it's ready and that results in awc being
		// terminated. Hence we ignore the signal.
		// See https://golang.org/pkg/os/signal/#hdr-Non_Go_programs_that_call_Go_code
		// for details.
		signal.Notify(make(chan os.Signal), syscall.SIGUSR1)
		sigUsr1HandlerInstalled = true
	}
}

func generateLoader(configPath string) []byte {
	tmpl, err := template.New("configloader").Parse(loaderTemplate)
	if err != nil {
		panic(err)
	}

	var buffer bytes.Buffer
	data := struct {
		Types string
		Deunionize string
		ConfigPath string
	}{Types, Deunionize, configPath}
	err = tmpl.Execute(io.Writer(&buffer), data)
	if err != nil {
		panic(err)
	}

	return buffer.Bytes()
}

//export awcConfigureKeyboard
func awcConfigureKeyboard(vendor C.uint32_t, token unsafe.Pointer, result *C.struct_AwcKeyboardConfig) {
	keyboardConfig := configs[token].ConfigureKeyboard(uint(vendor))
	result.Layout = C.CString(keyboardConfig.Layout)
}

//export awcGenerateErrorDisplayCmd
func awcGenerateErrorDisplayCmd(msg C.const_char_p, token unsafe.Pointer) *C.char {
	return C.CString(configs[token].ErrorDisplay(C.GoString(msg)))
}

func setKeyBindings(result *C.struct_AwcConfig, config *Config) {
	result.keyBindings = (*C.struct_AwcKeyBinding)(
		C.calloc(C.size_t(len(config.KeyBindings)), C.sizeof_struct_AwcKeyBinding))
	if result.keyBindings == nil {
		panic("Could not allocate keybinding memory")
	}
	keyBindings := (*[1<<16]C.struct_AwcKeyBinding)(unsafe.Pointer(result.keyBindings))
	for i, binding := range config.KeyBindings {
		keyBindings[i].code = C.uint(binding.Key.Code)
		if binding.Key.Sym != nil {
			keyBindings[i].sym = C.CString(*binding.Key.Sym)
		}
		if binding.Action.Execute != nil {
			keyBindings[i].action.execute = C.CString(*binding.Action.Execute)
		} else if binding.Action.MoveTo != nil {
			keyBindings[i].action.moveTo = C.CString(*binding.Action.MoveTo)
		} else if binding.Action.MoveToOutput != 0 {
			keyBindings[i].action.moveToOutput = C.uchar(binding.Action.MoveToOutput)
		} else if binding.Action.View != nil {
			keyBindings[i].action.view = C.CString(*binding.Action.View)
		} else if binding.Action.Close {
			keyBindings[i].action.close = true
		} else if binding.Action.ConfigReload {
			keyBindings[i].action.configReload = true
		} else if binding.Action.FocusDown {
			keyBindings[i].action.focusDown = true
		} else if binding.Action.FocusUp {
			keyBindings[i].action.focusUp = true
		} else if binding.Action.FocusPrimary {
			keyBindings[i].action.focusPrimary = true
		} else if binding.Action.FocusOutput != 0 {
			keyBindings[i].action.focusOutput = C.uchar(binding.Action.FocusOutput)
		} else if binding.Action.NextLayout {
			keyBindings[i].action.nextLayout = true
		} else if binding.Action.Sink {
			keyBindings[i].action.sink = true
		} else if binding.Action.SwapDown {
			keyBindings[i].action.swapDown = true
		} else if binding.Action.SwapUp {
			keyBindings[i].action.swapUp = true
		} else if binding.Action.SwapPrimary {
			keyBindings[i].action.swapPrimary = true
		} else if binding.Action.SwapWorkspaces {
			keyBindings[i].action.swapWorkspaces = true
		} else {
			if binding.Action.SwitchVT == 0 {
				panic(binding)
			}
			keyBindings[i].action.switchVt = C.uchar(binding.Action.SwitchVT)
		}
		keyBindings[i].mods = C.uint(binding.Modifiers)
	}
	result.numberOfKeyBindings = C.size_t(len(config.KeyBindings))
}

func setButtonBindings(result *C.struct_AwcConfig, config *Config) {
	result.buttonBindings = (*C.struct_AwcButtonBinding)(
		C.calloc(C.size_t(len(config.ButtonBindings)), C.sizeof_struct_AwcButtonBinding))
	if result.buttonBindings == nil {
		panic("Could not allocate button bindings memory")
	}
	buttonBindings := (*[1<<16]C.struct_AwcButtonBinding)(unsafe.Pointer(result.buttonBindings))
	for i, binding := range config.ButtonBindings {
		if binding.Action.Move {
			buttonBindings[i].action.move = true
		} else if binding.Action.Resize {
			buttonBindings[i].action.resize = true
		}
		buttonBindings[i].button = C.uint(binding.Button)
		buttonBindings[i].mods = C.uint(binding.Modifiers)
	}
	result.numberOfButtonBindings = C.size_t(len(config.ButtonBindings))
}

//export awcLoadConfig
func awcLoadConfig(path C.const_char_p, result *C.struct_AwcConfig) *C.char {
	installSigUsr1Handler()

	err := os.Setenv("AWC_TYPES", Types)
	if err != nil {
		panic(err)
	}

	var configPath string
	if path != nil {
		configPath = C.GoString(path)
	} else {
		var err error
		configPath, err = xdg.ConfigFile("awc/config.dhall")
		if err != nil {
			panic(err)
		}
	}

	var config Config

	err = dhall.Unmarshal(generateLoader(configPath), &config)
	if err != nil {
		return C.CString(err.Error())
	}

	token := C.malloc(1)
	if token == nil {
		panic("Could not allocate token memory")
	}
	configs[token] = config

	result.token = token
	result.borderWidth = C.uint(config.BorderWidth)
	config.ActiveBorderColor.applyTo(&result.activeBorderColor)
	config.InactiveBorderColor.applyTo(&result.inactiveBorderColor)

	setButtonBindings(result, &config)
	setKeyBindings(result, &config)

	result.outputs = (*C.struct_AwcOutputConfig)(
		C.calloc(C.size_t(len(config.Outputs)), C.sizeof_struct_AwcOutputConfig))
	if result.outputs == nil {
		panic("Could not allocate outputs memory")
	}
	outputs := (*[1<<16]C.struct_AwcOutputConfig)(unsafe.Pointer(result.outputs))
	for i, output := range config.Outputs {
		outputs[i].name = C.CString(output.Name)
		outputs[i].x = C.int(output.X)
		outputs[i].y = C.int(output.Y)
		outputs[i].scale = C.float(output.Scale)
	}
	result.numberOfOutputs = C.size_t(len(config.Outputs))

	return nil
}

//export awcConfigFree
func awcConfigFree(config *C.struct_AwcConfig) {
	keyBindings := (*[1<<16]C.struct_AwcKeyBinding)(unsafe.Pointer(config.keyBindings))
	for _, binding := range keyBindings[:config.numberOfKeyBindings] {
		C.free(unsafe.Pointer(binding.action.execute))
		C.free(unsafe.Pointer(binding.action.moveTo))
		C.free(unsafe.Pointer(binding.action.view))
		C.free(unsafe.Pointer(binding.sym))
	}

	outputs := (*[1<<16]C.struct_AwcOutputConfig)(unsafe.Pointer(config.outputs))
	for _, output := range outputs[:config.numberOfOutputs] {
		C.free(unsafe.Pointer(output.name))
	}

	C.free(unsafe.Pointer(config.buttonBindings))
	C.free(unsafe.Pointer(config.keyBindings))
}

//export awcConfigRelease
func awcConfigRelease(token unsafe.Pointer) {
	delete(configs, token)
}

//export awcAutostartPath
func awcAutostartPath() *C.char {
	path, err := xdg.ConfigFile("awc/autostart")
	if err != nil {
		panic(err)
	}
	return C.CString(path)
}

func main() {}

