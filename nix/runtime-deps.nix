{
  lib,
  brightnessctl,
  cliphist,
  ddcutil,
  wlsunset,
  wl-clipboard,
  wlr-randr,
  imagemagick,
  wget,
  python3,
  calendarSupport ? false,
}:
[
  brightnessctl
  cliphist
  ddcutil
  wlsunset
  wl-clipboard
  wlr-randr
  imagemagick
  wget
  (python3.withPackages (pp: lib.optional calendarSupport pp.pygobject3))
]
