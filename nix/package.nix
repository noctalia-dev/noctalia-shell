{
  version ? "dirty",
  extraPackages ? [ ],
  runtimeDeps ? [
    brightnessctl
    cliphist
    ddcutil
    wlsunset
    wl-clipboard
    wlr-randr
    imagemagick
    wget
    pulseaudio # pactl used by the ProjectM C++ plugin for audio source detection
    (python3.withPackages (pp: lib.optional calendarSupport pp.pygobject3))
  ],

  lib,
  stdenv,
  stdenvNoCC,
  cmake,
  ninja,
  pkg-config,
  # build
  qt6,
  quickshell,
  # C++ plugin deps
  libprojectm,
  libpulseaudio,
  # runtime deps
  brightnessctl,
  cliphist,
  ddcutil,
  wlsunset,
  wl-clipboard,
  wlr-randr,
  imagemagick,
  wget,
  pulseaudio,
  python3,
  wayland-scanner,
  # calendar support
  calendarSupport ? false,
  evolution-data-server,
  libical,
  glib,
  libsoup_3,
  json-glib,
  gobject-introspection,
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
        /Scripts/dev
        /nix
        /LICENSE
        /README.md
        /flake.nix
        /flake.lock
        /shell.nix
        /lefthook.yml
        /CLAUDE.md
        /CREDITS.md
      ]);
  };

  giTypelibPath = lib.makeSearchPath "lib/girepository-1.0" [
    evolution-data-server
    libical
    glib.out
    libsoup_3
    json-glib
    gobject-introspection
  ];

  # C++ QML plugin: embeds libprojectM + PulseAudio audio capture directly.
  # Used by LockScreenBackground as ProjectMItem (import qs.Multimedia).
  multimediaPlugin = stdenv.mkDerivation {
    pname = "noctalia-multimedia-plugin";
    inherit version;
    src = ../cpp;

    nativeBuildInputs = [
      cmake
      ninja
      pkg-config
      qt6.qtbase
      qt6.qtdeclarative
    ];

    buildInputs = [
      qt6.qtbase
      qt6.qtdeclarative
      libprojectm
      libpulseaudio
    ];

    # Plugin is a shared library, not an app — skip Qt app wrapping.
    dontWrapQtApps = true;

    meta.description = "ProjectM Qt Quick FBO plugin for noctalia-shell lock screen";
  };
in
stdenvNoCC.mkDerivation {
  pname = "noctalia-shell";
  inherit version src;

  nativeBuildInputs = [
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/noctalia-shell $out/bin $out/lib/qt6/qml
    cp -r . $out/share/noctalia-shell
    cp -r ${multimediaPlugin}/lib/qt6/qml/. $out/lib/qt6/qml/
    ln -s ${quickshell}/bin/qs $out/bin/noctalia-shell
    runHook postInstall
  '';

  preFixup = ''
    qtWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath (runtimeDeps ++ extraPackages)}
      --prefix XDG_DATA_DIRS : ${wayland-scanner}/share
      --set-default QS_CONFIG_PATH "$out/share/noctalia-shell"
      --prefix QML2_IMPORT_PATH : "$out/lib/qt6/qml"
      --set-default QSG_RHI_BACKEND opengl
      ${lib.optionalString calendarSupport "--prefix GI_TYPELIB_PATH : ${giTypelibPath}"}
    )
  '';

  meta = {
    description = "A sleek and minimal desktop shell thoughtfully crafted for Wayland, built with Quickshell.";
    homepage = "https://github.com/noctalia-dev/noctalia-shell";
    license = lib.licenses.mit;
    mainProgram = "noctalia-shell";
  };
}
