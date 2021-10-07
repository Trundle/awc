let List/foldLeft =
      https://prelude.dhall-lang.org/v20.2.0/List/foldLeft.dhall
        sha256:3c6ab57950fe644906b7bbdef0b9523440b6ee17773ebb8cbd41ffacb8bfab61

let Action =
      < Execute : Text
      | Expand
      | Close
      | ConfigReload
      | FocusDown
      | FocusUp
      | FocusPrimary
      | FocusOutput : Natural
      | GreedyView : Text
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

let OutputHud =
      { activeBackgroundColor : Color
      , activeForegroundColor : Color
      , inactiveBackgroundColor : Color
      , inactiveForegroundColor : Color
      }

let Layout
    : Type
    = ∀(Layout : Type) →
      ∀ ( layout
        : { choose : Layout → Layout → Layout
          , full : Layout
          , twoPane : Double → Double → Layout
          , rotated : Layout → Layout
          }
        ) →
        Layout

let choose
    : Layout → List Layout → Layout
    = λ(first : Layout) →
      λ(others : List Layout) →
      λ(_Layout : Type) →
      λ ( layout
        : { choose : _Layout → _Layout → _Layout
          , full : _Layout
          , twoPane : Double → Double → _Layout
          , rotated : _Layout → _Layout
          }
        ) →
        let adapt = λ(x : Layout) → x _Layout layout

        in  List/foldLeft
              Layout
              others
              _Layout
              ( λ(left : _Layout) →
                λ(right : Layout) →
                  layout.choose left (adapt right)
              )
              (adapt first)

let full
    : Layout
    = λ(Layout : Type) →
      λ ( layout
        : { choose : Layout → Layout → Layout
          , full : Layout
          , twoPane : Double → Double → Layout
          , rotated : Layout → Layout
          }
        ) →
        layout.full

let twoPane
    : Double → Double → Layout
    = λ(split : Double) →
      λ(delta : Double) →
      λ(Layout : Type) →
      λ ( layout
        : { choose : Layout → Layout → Layout
          , full : Layout
          , twoPane : Double → Double → Layout
          , rotated : Layout → Layout
          }
        ) →
        layout.twoPane split delta

let rotated
    : Layout → Layout
    = λ(wrapped : Layout) →
      λ(_Layout : Type) →
      λ ( layout
        : { choose : _Layout → _Layout → _Layout
          , full : _Layout
          , twoPane : Double → Double → _Layout
          , rotated : _Layout → _Layout
          }
        ) →
        let adapt
            : Layout → _Layout
            = λ(x : Layout) → x _Layout layout

        in  layout.rotated (adapt wrapped)

let LayoutOp =
      < Choose | Full | TwoPane : { split : Double, delta : Double } | Rotated >

let buildLayout
    : Layout → List LayoutOp
    = λ(layout : Layout) →
        layout
          (List LayoutOp)
          { choose =
              λ(a : List LayoutOp) →
              λ(b : List LayoutOp) →
                a # b # [ LayoutOp.Choose ]
          , full = [ LayoutOp.Full ]
          , twoPane =
              λ(split : Double) →
              λ(delta : Double) →
                [ LayoutOp.TwoPane { split, delta } ]
          , rotated =
              λ(wrapped : List LayoutOp) → wrapped # [ LayoutOp.Rotated ]
          }

let Config =
      { Type =
          { borderWidth : Natural
          , activeBorderColor : Color
          , inactiveBorderColor : Color
          , keyboards : List { type : KeyboardType, layout : Text }
          , layout : List LayoutOp
          , outputs :
              List { name : Text, x : Integer, y : Integer, scale : Double }
          , buttonBindings : List ButtonBinding
          , keyBindings : List KeyBinding
          , displayErrorCmd : Text
          , font : Text
          , modifier : Modifier
          , outputHud : OutputHud
          }
      , default =
        { borderWidth = 2
        , activeBorderColor = { r = 0xe3, g = 0xc5, b = 0x98, a = 0xff }
        , inactiveBorderColor = { r = 0x8a, g = 0x6e, b = 0x64, a = 0xff }
        , keyboards = [] : List { type : KeyboardType, layout : Text }
        , layout = [ LayoutOp.Full ]
        , outputs =
            [] : List { name : Text, x : Integer, y : Integer, scale : Double }
        , buttonBindings = [] : List ButtonBinding
        , keyBindings = [] : List KeyBinding
        , displayErrorCmd = "swaynag -m "
        , font = "PragmataPro Mono Liga"
        , modifier = Modifier.Logo
        , outputHud =
          { activeBackgroundColor = { r = 0x2a, g = 0x9d, b = 0x8f, a = 0xb2 }
          , activeForegroundColor = { r = 0xff, g = 0xff, b = 0xff, a = 0xff }
          , inactiveBackgroundColor = { r = 0xe9, g = 0xc4, b = 0x6a, a = 0xb2 }
          , inactiveForegroundColor = { r = 0x26, g = 0x46, b = 0x53, a = 0xff }
          }
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
    , Layout
    , Modifier
    , buildLayout
    , choose
    , full
    , rotated
    , twoPane
    }
