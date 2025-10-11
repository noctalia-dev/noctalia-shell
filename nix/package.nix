{
  self,
  pkgs,
  quickshell,
  system,
}:
let
  qs = quickshell.packages.${system}.default.override {
    withX11 = false;
    withI3 = true;
  };

  runtimeDeps =
    with pkgs;
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
    ++ lib.optionals (pkgs.stdenv.hostPlatform.isx86_64) [ gpu-screen-recorder ];

  fontconfig = pkgs.makeFontsConf {
    fontDirectories = [
      pkgs.roboto
      pkgs.inter-nerdfont
    ];
  };
in
pkgs.stdenv.mkDerivation {
  pname = "noctalia-shell";
  version = self.rev or self.dirtyRev or "dirty";
  src = ../.;

  nativeBuildInputs = [
    pkgs.gcc
    pkgs.makeWrapper
    pkgs.qt6.wrapQtAppsHook
  ];
  buildInputs = [
    qs
    pkgs.xkeyboard_config
    pkgs.qt6.qtbase
  ];
  propagatedBuildInputs = runtimeDeps;

  installPhase = ''
    mkdir -p $out/share/noctalia-shell
    cp -r ./* $out/share/noctalia-shell

    makeWrapper ${qs}/bin/qs $out/bin/noctalia-shell \
      --prefix PATH : "${pkgs.lib.makeBinPath runtimeDeps}" \
      --set FONTCONFIG_FILE "${fontconfig}" \
      --add-flags "-p $out/share/noctalia-shell"
  '';

  meta = {
    description = "A sleek and minimal desktop shell thoughtfully crafted for Wayland, built with Quickshell.";
    homepage = "https://github.com/noctalia-dev/noctalia-shell";
    license = pkgs.lib.licenses.mit;
    mainProgram = "noctalia-shell";
  };
}
