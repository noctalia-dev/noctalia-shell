{
  rev,
  lib,
  stdenv,
  makeWrapper,
  makeFontsConf,
  ddcutil,
  brightnessctl,
  cava,
  networkmanager,
  wl-clipboard,
  libnotify,
  bluez,
  bash,
  coreutils,
  findutils,
  file,
  material-symbols,
  roboto,
  inter-nerdfont,
  matugen,
  cliphist,
  swww,
  gpu-screen-recorder,
  gcc,
  qt6,
  quickshell,
  xkeyboard-config,
  extraRuntimeDeps ? [],
}: let
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
      gpu-screen-recorder
      libnotify
      matugen
      networkmanager
      swww
      wl-clipboard
    ]
    ++ extraRuntimeDeps;

  fontconfig = makeFontsConf {
    fontDirectories = [
      material-symbols
      roboto
      inter-nerdfont
    ];
  };
in
  stdenv.mkDerivation {
    pname = "noctalia-shell";
    version = "${rev}";
    src = ./..;

    nativeBuildInputs = [gcc makeWrapper qt6.wrapQtAppsHook];
    buildInputs = [quickshell xkeyboard-config qt6.qtbase];
    propagatedBuildInputs = runtimeDeps;

    installPhase = ''
      mkdir -p $out/share/noctalia-shell
      cp -r ./* $out/share/noctalia-shell

      makeWrapper ${quickshell}/bin/qs $out/bin/noctalia-shell \
      	--prefix PATH : "${lib.makeBinPath runtimeDeps}" \
      	--set FONTCONFIG_FILE "${fontconfig}" \
      	--add-flags "-p $out/share/noctalia-shell"
    '';

    meta = {
      description = "A sleek and minimal desktop shell thoughtfully crafted for Wayland, built with Quickshell.";
      homepage = "https://github.com/noctalia-dev/noctalia-shell";
      license = lib.licenses.mit;
      mainProgram = "noctalia-shell";
    };
  }
