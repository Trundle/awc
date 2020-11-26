===
awc
===

A Wayland compositor using `wlroots`_ written in Swift.

It is heavily inspired, conceptually as well as code-wise, from `XMonad`_.


How can I set a background, have a status bar or lock the screen?
=================================================================

Awc builds upon `wlroots`_, the same library that is used by Sway_. It also
implements a lot of wlroots protocols such as ``wlr-input-inhibitor``. That
means that quite a few tools work with Awc as well, such as `grim
<https://wayland.emersion.fr/grim/>`_, ``swaybg``, `swaylock
<https://github.com/swaywm/swaylock>`_ or `waybar
<https://github.com/Alexays/Waybar>`_.


Alternatives
============

There is a variety of other Wayland compositors if you don't like Awc. Following
are listed a few (without any claim to completeness):

* `hikari <https://hikari.acmelabs.space/>`_
* `river <https://github.com/ifreund/river>`_
* Sway_
* `Wayfire <https://wayfire.org/>`_

GNOME and KDE also work well with Waland.


.. _Sway: https://swaywm.org/
.. _wlroots: https://github.com/swaywm/wlroots
.. _XMonad: https://xmonad.org/
