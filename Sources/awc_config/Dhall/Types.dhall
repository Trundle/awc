let Action =
      < Execute : Text
      | Close
      | ConfigReload
      | FocusDown
      | FocusUp
      | FocusPrimary
      | FocusOutput : Natural
      | Sink
      | SwapDown
      | SwapUp
      | SwapPrimary
      | NextLayout
      | MoveTo : Text
      | MoveToOutput : Natural
      | SwapWorkspaces
      | SwitchVT : Natural
      | View : Text
      >

let Button = < Left | Right >

let ButtonAction = < Move | Resize >

let Key = < Code : Natural | Sym : Text >

let Modifier = < Alt | Ctrl | Logo | Shift >

let Color = { r : Natural, g : Natural, b : Natural, a : Natural }

let KeyBinding = { mods : List Modifier, key : Key, action : Action }

let ButtonBinding =
      { mods : List Modifier, button : Button, action : ButtonAction }

let Config =
      { Type =
          { borderWidth : Natural
          , activeBorderColor : Color
          , inactiveBorderColor : Color
          , configureKeyboard : ∀(vendor : Natural) → { layout : Text }
          , outputs :
              List { name : Text, x : Integer, y : Integer, scale : Double }
          , shouldFloat : ∀(appId : Text) → Bool
          , buttonBindings : List ButtonBinding
          , keyBindings : List KeyBinding
          , errorDisplay : ∀(msg : Text) → Text
          }
      , default =
        { borderWidth = 2
        , activeBorderColor = { r = 0xe3, g = 0xc5, b = 0x98, a = 0xff }
        , inactiveBorderColor = { r = 0x8a, g = 0x6e, b = 0x64, a = 0xff }
        , configureKeyboard = λ(vendor : Natural) → { layout = "de" }
        , outputs =
            [] : List { name : Text, x : Integer, y : Integer, scale : Double }
        , shouldFloat = λ(_ : Text) → False
        , buttonBindings = [] : List ButtonBinding
        , keyBindings = [] : List KeyBinding
        , errorDisplay = λ(msg : Text) → "swaynag -m \"${msg}\""
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
    , Modifier
    }
