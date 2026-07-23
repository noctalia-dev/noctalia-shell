{
  lib,
  config,
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
  md4c,
  libsecret,
  libsodium,
  stb,
  fetchFromGitHub,
  nlohmann_json,
  tomlplusplus,
  wireplumber,
  jemalloc,
  makeWrapper,
  git,
  autoAddDriverRunpath,
  cudaSupport ? config.cudaSupport,
}:

let
  inherit (builtins) head match readFile;
  version = head (match ".*version: '([0-9][^']+)'.*" (readFile ../meson.build));

  # libprojectm 4.x links against desktop GL by default, but noctalia uses an
  # EGL/GLESv2 share group. Toggle the upstream CMake ENABLE_GLES option so the
  # library's GL paths match the contexts we hand it. Also patch the installed
  # pkg-config file: upstream emits "-l:projectM-4" (GCC exact-filename syntax)
  # whose literal filename does not exist (the real .so is "libprojectM-4.so"),
  # so the linker can't resolve it. Rewrite to the conventional "-lprojectM-4".
  #
  # (The former ./patches/libprojectm-null-texture-descriptor.patch guarded
  # TextureSamplerDescriptor::Empty() against a null m_texture; that null check
  # is now upstream in the libprojectm version nixpkgs ships, so the patch was
  # dropped.)
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

  stb' = stb.overrideAttrs (_: {
    version = "unstable-2025-10-26";
    src = fetchFromGitHub {
      owner = "nothings";
      repo = "stb";
      rev = "f1c79c02822848a9bed4315b12c8c8f3761e1296";
      hash = "sha256-BlyXJtAI7WqXCTT3ylww8zoG0hBxaojJnQDvdQOXJPE=";
    };
  });
in
stdenv.mkDerivation {
  pname = "noctalia";
  inherit version;

  src = lib.cleanSource ./..;

  postFixup = ''
    wrapProgram $out/bin/noctalia \
      --prefix PATH : ${lib.makeBinPath [ git ]}
  '';

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wayland-scanner
    jemalloc
    makeWrapper
  ]
  ++ lib.optional cudaSupport autoAddDriverRunpath;

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
    wireplumber
    pam
    curl
    libwebp
    glib
    polkit
    librsvg
    libprojectm-gles
    libqalculate
    libxml2
    md4c
    libsecret
    libsodium
    stb'
    nlohmann_json
    tomlplusplus
  ];

  mesonBuildType = "release";

  ninjaFlags = [ "-v" ];

  meta = with lib; {
    description = "A sleek, customizable desktop shell crafted for Wayland.";
    homepage = "https://github.com/noctalia-dev/noctalia";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "noctalia";
  };
}
