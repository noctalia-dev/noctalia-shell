{
  lib,
  stdenv,
  meson,
  ninja,
  pkg-config,
  wayland-scanner,
  wayland,
  wayland-protocols,
  libGL,
  libglvnd,
  freetype,
  fontconfig,
  cairo,
  pango,
  harfbuzz,
  libxkbcommon,
  sdbus-cpp_2,
  systemd,
  pipewire,
  pam,
  curl,
  libwebp,
  glib,
  polkit,
  librsvg,
  libprojectm,
  libqalculate,
  libxml2,
  jemalloc,
  source ? lib.cleanSource ./..,
  shortRev,
  version,
}:

let
  # libprojectm 4.x links against desktop GL by default, but noctalia uses an
  # EGL/GLESv2 share group. Toggle the upstream CMake ENABLE_GLES option so the
  # library's GL paths match the contexts we hand it. Also patch the installed
  # pkg-config file: upstream emits "-l:projectM-4" (GCC exact-filename syntax)
  # whose literal filename does not exist (the real .so is "libprojectM-4.so"),
  # so the linker can't resolve it. Rewrite to the conventional "-lprojectM-4".
  libprojectm-gles = libprojectm.overrideAttrs (old: {
    pname = "libprojectm-gles";
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [
      "-DENABLE_GLES=ON"
    ];
    buildInputs = (old.buildInputs or [ ]) ++ [ libglvnd ];
    postFixup = (old.postFixup or "") + ''
      for pc in "$out"/lib/pkgconfig/projectM-4*.pc; do
        sed -i 's/-l:projectM-4/-lprojectM-4/g' "$pc"
        # pkg-config is case-sensitive; meson lower-cases dependency names
        # when caching lookups. Provide a lowercase symlink alongside the
        # canonical capital-M name so dependency('projectM-4') resolves.
        ln -sf "$(basename "$pc")" "$(dirname "$pc")/$(basename "$pc" | tr '[:upper:]' '[:lower:]')"
      done
    '';
  });
in
stdenv.mkDerivation {
  pname = "noctalia";
  inherit version;

  src = source;

  postPatch = ''
    # Remove -march=native and -mtune=native for reproducible builds
    sed -i "s/'-march=native', '-mtune=native',//" meson.build

    sed -i "s|@VCS_TAG@|${shortRev}|g" src/core/git_revision.h.in
  '';

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wayland-scanner
    jemalloc
  ];

  buildInputs = [
    wayland
    wayland-protocols
    libGL
    libglvnd
    freetype
    fontconfig
    cairo
    pango
    harfbuzz
    libxkbcommon
    sdbus-cpp_2
    systemd
    pipewire
    pam
    curl
    libwebp
    glib
    polkit
    librsvg
    libprojectm-gles
    libqalculate
    libxml2
  ];

  mesonBuildType = "release";

  ninjaFlags = [ "-v" ];

  meta = with lib; {
    description = "A lightweight Wayland shell and bar built directly on Wayland + OpenGL ES";
    homepage = "https://github.com/noctalia-dev/noctalia-shell";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "noctalia";
  };
}
