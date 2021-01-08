let Natural/equal =
      https://prelude.dhall-lang.org/v19.0.0/Natural/equal sha256:7f108edfa35ddc7cebafb24dc073478e93a802e13b5bc3fd22f4768c9b066e60

let Natural/lessThan =
      https://prelude.dhall-lang.org/v19.0.0/Natural/lessThan sha256:3381b66749290769badf8855d8a3f4af62e8de52d1364d838a9d1e20c94fa70c

let List/map =
      https://prelude.dhall-lang.org/v19.0.0/List/map sha256:dd845ffb4568d40327f2a817eb42d1c6138b929ca758d50bc33112ef3c885680

let Types = env:AWC_TYPES

let Bitset/isSet =
      λ(n : Natural) →
      λ(set : Natural) →
        if    Natural/equal n 1
        then  Natural/odd set
        else  if Natural/lessThan set n
        then  False
        else  let DivAcc = { quot : Natural, rem : Natural }

              let quotMod
                          -- Calculates (set / n) % n
                          =
                    Natural/fold
                      set
                      DivAcc
                      ( λ(acc : DivAcc) →
                          if    Natural/lessThan acc.rem n
                          then  acc
                          else  let newQuot =
                                      if    Natural/equal (acc.quot + 1) n
                                      then  0
                                      else  acc.quot + 1

                                in  { quot = newQuot
                                    , rem = Natural/subtract n acc.rem
                                    }
                      )
                      { quot = 0, rem = set }

              in  Natural/odd quotMod.quot

let deunionizeAction =
      λ(action : Types.Action) →
        let empty =
              { execute = None Text
              , close = False
              , configReload = False
              , focusDown = False
              , focusUp = False
              , focusPrimary = False
              , focusOutput = 0
              , sink = False
              , swapDown = False
              , swapUp = False
              , swapPrimary = False
              , swapWorkspaces = False
              , nextLayout = False
              , moveTo = None Text
              , moveToOutput = 0
              , switchVt = 0
              , view = None Text
              }

        in  merge
              { Execute = λ(cmd : Text) → empty ⫽ { execute = Some cmd }
              , Close = empty ⫽ { close = True }
              , ConfigReload = empty ⫽ { configReload = True }
              , FocusDown = empty ⫽ { focusDown = True }
              , FocusUp = empty ⫽ { focusUp = True }
              , FocusPrimary = empty ⫽ { focusPrimary = True }
              , FocusOutput = λ(n : Natural) → empty ⫽ { focusOutput = n }
              , Sink = empty ⫽ { sink = True }
              , SwapDown = empty ⫽ { swapDown = True }
              , SwapUp = empty ⫽ { swapUp = True }
              , SwapPrimary = empty ⫽ { swapPrimary = True }
              , SwapWorkspaces = empty ⫽ { swapWorkspaces = True }
              , NextLayout = empty ⫽ { nextLayout = True }
              , MoveTo = λ(tag : Text) → empty ⫽ { moveTo = Some tag }
              , MoveToOutput = λ(n : Natural) → empty ⫽ { moveToOutput = n }
              , SwitchVT = λ(vt : Natural) → empty ⫽ { switchVt = vt }
              , View = λ(tag : Text) → empty ⫽ { view = Some tag }
              }
              action

let deunionizeModifier =
      λ(mod : Types.Modifier) →
        merge { Alt = 8, Ctrl = 4, Logo = 64, Shift = 1 } mod

let DeunionizedButtonBinding =
      { action : { move : Bool, resize : Bool }
      , button : Natural
      , mods : Natural
      }

let deunionizeButton =
      λ(button : Types.Button) → merge { Left = 1, Right = 3 } button

let deunionizeButtonAction =
      λ(action : Types.ButtonAction) →
        let empty = { move = False, resize = False }

        in  merge
              { Move = empty ⫽ { move = True }
              , Resize = empty ⫽ { resize = True }
              }
              action

let deunionizeButtonBinding =
      λ(binding : Types.ButtonBinding) →
        { action = deunionizeButtonAction binding.action
        , mods =
            List/fold
              Types.Modifier
              binding.mods
              Natural
              ( λ(mod : Types.Modifier) →
                λ(acc : Natural) →
                  let deunionizedMod = deunionizeModifier mod

                  in  if    Bitset/isSet deunionizedMod acc
                      then  acc
                      else  acc + deunionizedMod
              )
              0
        , button = deunionizeButton binding.button
        }

let deunionizeKey =
      λ(key : Types.Key) →
        merge
          { Code = λ(code : Natural) → { code, sym = None Text }
          , Sym = λ(sym : Text) → { code = 0, sym = Some sym }
          }
          key

let DeunionizedKeyBinding =
      { action :
          { execute : Optional Text
          , close : Bool
          , configReload : Bool
          , focusDown : Bool
          , focusUp : Bool
          , focusPrimary : Bool
          , focusOutput : Natural
          , sink : Bool
          , swapDown : Bool
          , swapUp : Bool
          , swapPrimary : Bool
          , swapWorkspaces : Bool
          , nextLayout : Bool
          , moveTo : Optional Text
          , moveToOutput : Natural
          , switchVt : Natural
          , view : Optional Text
          }
      , key : { code : Natural, sym : Optional Text }
      , mods : Natural
      }

let deunionizeKeyBinding =
      λ(binding : Types.KeyBinding) →
        { action = deunionizeAction binding.action
        , mods =
            List/fold
              Types.Modifier
              binding.mods
              Natural
              ( λ(mod : Types.Modifier) →
                λ(acc : Natural) →
                  let deunionizedMod = deunionizeModifier mod

                  in  if    Bitset/isSet deunionizedMod acc
                      then  acc
                      else  acc + deunionizedMod
              )
              0
        , key = deunionizeKey binding.key
        }

in  λ(config : Types.Config.Type) →
        config.{ borderWidth
               , activeBorderColor
               , inactiveBorderColor
               , configureKeyboard
               , outputs
               , errorDisplay
               }
      ⫽ { buttonBindings =
            List/map
              Types.ButtonBinding
              DeunionizedButtonBinding
              deunionizeButtonBinding
              config.buttonBindings
        , keyBindings =
            List/map
              Types.KeyBinding
              DeunionizedKeyBinding
              deunionizeKeyBinding
              config.keyBindings
        }
