===
awc
===

A Wayland compositor using `wlroots`_ written in Swift.

It is heavily inspired, conceptually as well as code-wise, from `XMonad`_.


Configuration
=============

Awc uses `Dhall <https://dhall-lang.org/>`_ as language for its configuration.
It automatically loads a configuration located under
``$XDG_CONFIG_DIRS/awc/config.dhall``, typically ``~/.config/awc/config.dhall``,
on startup.

Following is an empty config that uses all the defaults:

.. code-block:: dhall

   let Types = env:AWC_TYPES in Types.Config::{=}

That's probably a pretty boring configuration, as it doesn't define any
keybindings and hence it's not possible to switch any windows or to do anything.
You likely want to override the keybindings with some actions:

.. code-block:: dhall

   let mod = Types.Modifier.Logo
   in Types::Config{
   , keyBindings =
       [ { mods = [ mod ]
         , key = Types.Key.Sym "j"
         , action = Types.Action.FocusDown
         }
       , { mods = [ mod ]
         , key = Types.Key.Sym "k"
         , action = Types.Action.FocusUp
         }
       , { mods = [ mod, Types.Modifier.Shift ]
         , key = Types.Key.Sym "Return"
         , action = Types.Action.Execute "kitty"
         }
       ]
   }

For a list of available actions, see `Sources/awc_config/Dhall/Types.dhall
<https://github.com/Trundle/awc/blob/main/Sources/awc_config/Dhall/Types.dhall>`_.

Note that reloading the configuration when running Awc currently doesn't affect
all settings (e.g. border width).


How can I set a background, have a status bar or lock the screen?
=================================================================

Awc builds upon `wlroots`_, the same library that is used by Sway_. It also
implements a lot of wlroots protocols such as ``wlr-input-inhibitor``. That
means that quite a few tools work with Awc as well, such as `grim
<https://wayland.emersion.fr/grim/>`_, ``swaybg``, `swaylock
<https://github.com/swaywm/swaylock>`_ or `waybar
<https://github.com/Alexays/Waybar>`_.


How to build
============

Install the following dependencies and then run ``make``.

Dependencies
------------

* Rust
* Swift 5.3 (or newer)
* GLESv2
* libinput
* pixman
* pkg-config
* wayland
* wayland-protocols
* wlroots (>= 0.14.0)
* xcb
* xkbcommon
* openssl


Alternatives
============

There is a variety of other Wayland compositors if you don't like Awc. Following
are listed a few (without any claim to completeness):

* `hikari <https://hikari.acmelabs.space/>`_
* `river <https://github.com/ifreund/river>`_
* Sway_
* `vivarium <https://github.com/inclement/vivarium>`_
* `Wayfire <https://wayfire.org/>`_

GNOME and KDE also work well with Wayland. See also `wlroot's project list
<https://github.com/swaywm/wlroots/wiki/Projects-which-use-wlroots>`_.


License
=======

Awc is released under the Apache License, Version 2.0. See ``LICENSE``
or http://www.apache.org/licenses/LICENSE-2.0.html for details.

Design-wise, Awc is heavily inspired by XMonad_ (e.g. zippers, layouts), which
is::

   Copyright (c) 2007,2008 Spencer Janssen
   Copyright (c) 2007,2008 Don Stewart

and released under `a BSD license
<https://github.com/xmonad/xmonad/blob/master/LICENSE>`_.


.. _Sway: https://swaywm.org/
.. _wlroots: https://github.com/swaywm/wlroots
.. _XMonad: https://xmonad.org/
