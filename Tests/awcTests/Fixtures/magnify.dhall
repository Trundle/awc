let Types = env:AWC_TYPES

in  Types.Config::{ layout = Types.buildLayout (Types.magnify 1.5 (Types.twoPane 0.5 0.1)) }
