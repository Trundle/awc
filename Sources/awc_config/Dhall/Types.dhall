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
      | SwapWorkspaceTagWith : Text
      | SwitchVT : Natural
      | View : Text
      >

let Button = < Left | Right >

let ButtonAction = < Move | Resize | ResizeByFrame >

let WindowSelection = < Focused | UnderCursor >

let KeyboardType = < Builtin | External >

let Key = < Code : Natural | Sym : Text >

let Modifier = < Alt | Ctrl | Logo | Mod5 | Shift >

let Color = { r : Natural, g : Natural, b : Natural, a : Natural }

let Direction = < Horizontal | Vertical >

let KeyBinding = { mods : List Modifier, key : Key, action : Action }

let ButtonBinding =
      { mods : List Modifier
      , button : Button
      , action : ButtonAction
      , window : WindowSelection
      }

let OutputHud =
      { activeBackground : Color
      , activeForeground : Color
      , activeGlow : Color
      , inactiveBackground : Color
      , inactiveForeground : Color
      }

let Layout
    : Type
    = ∀(Layout : Type) →
      ∀ ( layout
        : { choose : Layout → Layout → Layout
          , full : Layout
          , twoPane : Double → Double → Layout
          , magnify : Double → Layout → Layout
          , reflected : Direction → Layout → Layout
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
          , magnify : Double → _Layout → _Layout
          , reflected : Direction → _Layout → _Layout
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
          , magnify : Double → Layout → Layout
          , reflected : Direction → Layout → Layout
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
          , magnify : Double → Layout → Layout
          , reflected : Direction → Layout → Layout
          , rotated : Layout → Layout
          }
        ) →
        layout.twoPane split delta

let magnify
    : Double → Layout → Layout
    = λ(magnification : Double) →
      λ(wrapped : Layout) →
      λ(_Layout : Type) →
      λ ( layout
        : { choose : _Layout → _Layout → _Layout
          , full : _Layout
          , twoPane : Double → Double → _Layout
          , magnify : Double → _Layout → _Layout
          , reflected : Direction → _Layout → _Layout
          , rotated : _Layout → _Layout
          }
        ) →
        let adapt
            : Layout → _Layout
            = λ(x : Layout) → x _Layout layout

        in  layout.magnify magnification (adapt wrapped)

let reflected
    : Direction → Layout → Layout
    = λ(direction : Direction) →
      λ(wrapped : Layout) →
      λ(_Layout : Type) →
      λ ( layout
        : { choose : _Layout → _Layout → _Layout
          , full : _Layout
          , twoPane : Double → Double → _Layout
          , magnify : Double → _Layout → _Layout
          , reflected : Direction → _Layout → _Layout
          , rotated : _Layout → _Layout
          }
        ) →
        let adapt
            : Layout → _Layout
            = λ(x : Layout) → x _Layout layout

        in  layout.reflected direction (adapt wrapped)

let rotated
    : Layout → Layout
    = λ(wrapped : Layout) →
      λ(_Layout : Type) →
      λ ( layout
        : { choose : _Layout → _Layout → _Layout
          , full : _Layout
          , twoPane : Double → Double → _Layout
          , magnify : Double → _Layout → _Layout
          , reflected : Direction → _Layout → _Layout
          , rotated : _Layout → _Layout
          }
        ) →
        let adapt
            : Layout → _Layout
            = λ(x : Layout) → x _Layout layout

        in  layout.rotated (adapt wrapped)

let LayoutOp =
      < Choose
      | Full
      | TwoPane : { split : Double, delta : Double }
      | Magnify : Double
      | Reflected : Direction
      | Rotated
      >

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
          , magnify =
              λ(magnification : Double) →
              λ(wrapped : List LayoutOp) →
                wrapped # [ LayoutOp.Magnify magnification ]
          , reflected =
              λ(direction : Direction) →
              λ(wrapped : List LayoutOp) →
                wrapped # [ LayoutOp.Reflected direction ]
          , rotated =
              λ(wrapped : List LayoutOp) → wrapped # [ LayoutOp.Rotated ]
          }

let Config =
      { Type =
          { borderWidth : Natural
          , keyboards : List { type : KeyboardType, layout : Text }
          , layout : List LayoutOp
          , outputs :
              List { name : Text, x : Integer, y : Integer, scale : Double }
          , buttonBindings : List ButtonBinding
          , keyBindings : List KeyBinding
          , displayErrorCmd : Text
          , font : Text
          , modifier : Modifier
          , colors :
              { borders : { active : Color, inactive : Color }
              , outputHud : OutputHud
              , resizeFrame : Color
              }
          , workspaces : List Text
          }
      , default =
        { borderWidth = 2
        , keyboards = [] : List { type : KeyboardType, layout : Text }
        , layout = [ LayoutOp.Full ]
        , outputs =
            [] : List { name : Text, x : Integer, y : Integer, scale : Double }
        , buttonBindings = [] : List ButtonBinding
        , keyBindings = [] : List KeyBinding
        , displayErrorCmd = "swaynag -m "
        , font = "PragmataPro Mono Liga"
        , modifier = Modifier.Logo
        , colors =
          { borders =
            { active = { r = 0xe3, g = 0xc5, b = 0x98, a = 0xff }
            , inactive = { r = 0x18, g = 0xca, b = 0xe6, a = 0xff }
            }
          , outputHud =
            { activeBackground = { r = 0x60, g = 0xa8, b = 0x6f, a = 0xb2 }
            , activeForeground = { r = 0xff, g = 0xff, b = 0xff, a = 0xff }
            , activeGlow = { r = 0x92, g = 0xff, b = 0xf1, a = 0xb2 }
            , inactiveBackground = { r = 0x9e, g = 0x22, b = 0x91, a = 0xb2 }
            , inactiveForeground = { r = 0xff, g = 0xff, b = 0xff, a = 0xff }
            }
          , resizeFrame = { r = 0x18, g = 0xca, b = 0xe6, a = 0x80 }
          }
        , workspaces = [ "1", "2", "3", "4", "5", "6", "7", "8", "9" ]
        }
      }

in  { Action
    , Button
    , ButtonAction
    , ButtonBinding
    , Color
    , Config
    , Direction
    , Key
    , KeyBinding
    , KeyboardType
    , Layout
    , Modifier
    , WindowSelection
    , buildLayout
    , choose
    , full
    , magnify
    , reflected
    , rotated
    , twoPane
    }
