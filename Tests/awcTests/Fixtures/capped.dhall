let Types = env:AWC_TYPES

in  Types.Config::{
    , layout = Types.buildLayout (Types.capped 3 (Types.tiled 0.5 0.1))
    }
