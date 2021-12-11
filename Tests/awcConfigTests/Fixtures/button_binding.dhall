let Types = env:AWC_TYPES
let binding =
  { mods = [ Types.Modifier.Alt, Types.Modifier.Alt, Types.Modifier.Shift ]
  , button = Types.Button.Left
  , action = Types.ButtonAction.Move
  , window = Types.WindowSelection.Focused
  }
in Types.Config::{buttonBindings = [ binding ] }