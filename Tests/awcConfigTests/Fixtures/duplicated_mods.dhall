let Types = env:AWC_TYPES
let binding =
  { mods = [ Types.Modifier.Alt, Types.Modifier.Alt ]
  , key = Types.Key.Code 42
  , action = Types.Action.Close
  }
in Types.Config::{keyBindings = [ binding ] }