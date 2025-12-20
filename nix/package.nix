{
  version ? "dirty",
  lib,
  stdenvNoCC,
  # build
  qt6,
  quickshell,
  # runtime deps
  brightnessctl,
  cava,
  cliphist,
  ddcutil,
  matugen,
  wlsunset,
  wl-clipboard,
  imagemagick,
  wget,
  gpu-screen-recorder, # optional
}:
let
  src = lib.cleanSourceWith {
    src = ../.;
    filter =
      path: type:
      !(builtins.any (prefix: lib.path.hasPrefix (../. + prefix) (/. + path)) [
        /.github
        /.gitignore
        /Assets/Screenshots
        /Bin/dev
        /nix
        /LICENSE
        /README.md
        /flake.nix
        /flake.lock
        /shell.nix
        /lefthook.yml
        /CLAUDE.md
      ]);
  };

  runtimeDeps = [
    brightnessctl
    cava
    cliphist
    ddcutil
    matugen
    wlsunset
    wl-clipboard
    imagemagick
    wget
  ]
  ++ lib.optionals (stdenvNoCC.hostPlatform.system == "x86_64-linux") [
    gpu-screen-recorder
  ];
in
stdenvNoCC.mkDerivation {
  pname = "noctalia-shell";
  inherit version src;

  nativeBuildInputs = [
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtmultimedia
  ];

  installPhase = ''
    mkdir -p $out/share/noctalia-shell $out/bin
    cp -r . $out/share/noctalia-shell
    ln -s ${quickshell}/bin/qs $out/bin/noctalia-shell
  '';

  preFixup = ''
    qtWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
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
