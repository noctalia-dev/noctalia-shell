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
  libjxl,
  libsndfile,
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
  libical,
  wireplumber,
  jemalloc,
  makeWrapper,
  git,
  gsettings-desktop-schemas,
  autoAddDriverRunpath,
  # DEPRECATED: no longer affects the build; kept for `.override` compat.
  cudaSupport ? config.cudaSupport,
}:

let
  inherit (builtins) head match readFile;
  version = head (match ".*version: '([0-9][^']+)'.*" (readFile ../meson.build));

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
lib.warnIf cudaSupport
  "noctalia: `cudaSupport` no longer has any effect (autoAddDriverRunpath is now always applied); this argument will be removed in the future."
  stdenv.mkDerivation
  {
    pname = "noctalia";
    inherit version;

    src = lib.cleanSource ./..;

    postFixup = ''
      wrapProgram $out/bin/noctalia \
        --prefix PATH : ${lib.makeBinPath [ git ]} \
        --prefix XDG_DATA_DIRS : "${glib.getSchemaDataDirPath gsettings-desktop-schemas}"

      $out/bin/noctalia completions bash | install -D /dev/stdin $out/share/bash-completion/completions/noctalia
      $out/bin/noctalia completions zsh  | install -D /dev/stdin $out/share/zsh/site-functions/_noctalia
      $out/bin/noctalia completions fish | install -D /dev/stdin $out/share/fish/vendor_completions.d/noctalia.fish
    '';

    nativeBuildInputs = [
      meson
      ninja
      pkg-config
      wayland-scanner
      jemalloc
      makeWrapper
      autoAddDriverRunpath
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
      wireplumber
      pam
      curl
      libwebp
      libjxl
      libsndfile
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
      libical
    ];

    mesonBuildType = "release";

    mesonFlags = [ "-Dtests=disabled" ];

    ninjaFlags = [ "-v" ];

    meta = with lib; {
      description = "A sleek, customizable desktop shell crafted for Wayland.";
      homepage = "https://github.com/noctalia-dev/noctalia";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "noctalia";
    };
  }
