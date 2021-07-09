let Action =
      < Execute : Text
      | Expand
      | Close
      | ConfigReload
      | FocusDown
      | FocusUp
      | FocusPrimary
      | FocusOutput : Natural
      | Shrink
      | Sink
      | SwapDown
      | SwapUp
      | SwapPrimary
      | NextLayout
      | ResetLayouts
      | MoveTo : Text
      | MoveToOutput : Natural
      | SwapWorkspaces
      | SwitchVT : Natural
      | View : Text
      >

let Button = < Left | Right >

let ButtonAction = < Move | Resize >

let KeyboardType = < Builtin | External >

let Key = < Code : Natural | Sym : Text >

let Modifier = < Alt | Ctrl | Logo | Mod5 | Shift >

let Color = { r : Natural, g : Natural, b : Natural, a : Natural }

let KeyBinding = { mods : List Modifier, key : Key, action : Action }

let ButtonBinding =
      { mods : List Modifier, button : Button, action : ButtonAction }

let Config =
      { Type =
          { borderWidth : Natural
          , activeBorderColor : Color
          , inactiveBorderColor : Color
          , keyboards : List { type : KeyboardType, layout : Text }
          , outputs :
              List { name : Text, x : Integer, y : Integer, scale : Double }
          , buttonBindings : List ButtonBinding
          , keyBindings : List KeyBinding
          , displayErrorCmd : Text
          }
      , default =
        { borderWidth = 2
        , activeBorderColor = { r = 0xe3, g = 0xc5, b = 0x98, a = 0xff }
        , inactiveBorderColor = { r = 0x8a, g = 0x6e, b = 0x64, a = 0xff }
        , keyboards = [] : List { type : KeyboardType, layout : Text }
        , outputs =
            [] : List { name : Text, x : Integer, y : Integer, scale : Double }
        , buttonBindings = [] : List ButtonBinding
        , keyBindings = [] : List KeyBinding
        , displayErrorCmd = "swaynag -m "
        }
      }

in  { Action
    , Button
    , ButtonAction
    , ButtonBinding
    , Color
    , Config
    , Key
    , KeyBinding
    , KeyboardType
    , Modifier
    }
