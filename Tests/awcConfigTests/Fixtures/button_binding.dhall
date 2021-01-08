let Types = env:AWC_TYPES
let binding =
  { mods = [ Types.Modifier.Alt, Types.Modifier.Alt ]
  , button = Types.Button.Left
  , action = Types.ButtonAction.Move
  }
in Types.Config::{buttonBindings = [ binding ] }