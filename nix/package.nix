{
  version ? "dirty",
  lib,
  stdenv,
  # build
  gcc,
  qt6,
  quickshell,
  xkeyboard_config,
  # runtime deps
  bash,
  bluez,
  brightnessctl,
  cava,
  cliphist,
  coreutils,
  ddcutil,
  file,
  findutils,
  libnotify,
  matugen,
  networkmanager,
  wlsunset,
  wl-clipboard,
  gpu-screen-recorder, # optional
  # fonts
  makeFontsConf,
  roboto,
  inter-nerdfont,
}: let
  src = lib.cleanSourceWith {
    src = ../.;
    filter = path: _type:
      !(builtins.any (prefix: lib.path.hasPrefix (../. + prefix) (/. + path)) [
        /.github
        /Assets/Screenshots
        /Assets/Wallpaper
        /Bin/dev
        /nix
        /LICENSE
        /README.md
        /flake.nix
        /flake.lock
      ]);
  };

  runtimeDeps =
    [
      bash
      bluez
      brightnessctl
      cava
      cliphist
      coreutils
      ddcutil
      file
      findutils
      libnotify
      matugen
      networkmanager
      wlsunset
      wl-clipboard
    ]
    ++ lib.optionals stdenv.hostPlatform.isx86_64 [gpu-screen-recorder];

  fontconfig = makeFontsConf {
    fontDirectories = [
      roboto
      inter-nerdfont
    ];
  };
in
  stdenv.mkDerivation {
    pname = "noctalia-shell";
    inherit version src;

    nativeBuildInputs = [
      gcc
      qt6.wrapQtAppsHook
    ];
    buildInputs = [
      quickshell
      xkeyboard_config
      qt6.qtbase
    ];
    propagatedBuildInputs = runtimeDeps;

    installPhase = ''
      mkdir -p $out/share/noctalia-shell $out/bin
      cp -r ./* $out/share/noctalia-shell
      cp ${quickshell}/bin/qs $out/bin/noctalia-shell
    '';

    preFixup = ''
      qtWrapperArgs+=(
        --prefix PATH : ${lib.makeBinPath runtimeDeps}
        --set FONTCONFIG_FILE ${fontconfig}
        --add-flags "-p $out/share/noctalia-shell"
      )
    '';

    meta = {
      description = "A sleek and minimal desktop shell thoughtfully crafted for Wayland, built with Quickshell.";
      homepage = "https://github.com/noctalia-dev/noctalia-shell";
      license = lib.licenses.mit;
      mainProgram = "noctalia-shell";
    };
  }
