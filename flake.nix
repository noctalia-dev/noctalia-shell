{
  description = "Noctalia - A lightweight Wayland shell and bar";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      mesonBuild = builtins.readFile ./meson.build;
      rawVersion =
        let
          m = builtins.match ".*version:[[:space:]]*'([^']+)'.*" mesonBuild;
        in
        if m == null then "0.0.0" else builtins.head m;

      date = lib.substring 0 8 (self.sourceInfo.lastModifiedDate or "19700101");
      version = "${rawVersion}-unstable-${date}";
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          self',
          pkgs,
          lib,
          ...
        }:
        {
          packages = {
            default = self'.packages.noctalia;
            noctalia = pkgs.stdenv.mkDerivation {
              pname = "noctalia";
              inherit version;

              src = lib.cleanSource ./.;

              postPatch = ''
                substituteInPlace meson.build \
                  --replace-fail "'-march=native', '-mtune=native'," ""
              '';

              nativeBuildInputs = with pkgs; [
                meson
                ninja
                pkg-config
                wayland-scanner
              ];

              buildInputs = with pkgs; [
                wayland
                wayland-protocols
                libepoxy
                mesa
                libglvnd
                freetype
                fontconfig
                cairo
                pango
                libwebp
                libxkbcommon
                sdbus-cpp_2
                systemd
                pipewire
                pam
                curl
              ];

              NIX_CFLAGS_COMPILE = "-Wno-pedantic -Wno-conversion";
              mesonBuildType = "release";
              ninjaFlags = [ "-v" ];

              meta = {
                description = "A lightweight Wayland shell and bar built directly on Wayland + OpenGL ES";
                homepage = "https://github.com/noctalia-dev/noctalia-shell";
                license = lib.licenses.mit;
                platforms = lib.platforms.linux;
                mainProgram = "noctalia";
                maintainers = with lib.maintainers; [ lonerOrz ];

              };
            };
          };

          devShells.default = pkgs.mkShell {
            inputsFrom = [ self'.packages.default ];

            nativeBuildInputs = with pkgs; [
              # Workflow & Hooks
              just
              lefthook

              # Formatting (required by justfile)
              clang-tools
              gnugrep
              gnused
              findutils

              # Debugging
              gdb
            ];

            shellHook = ''
              # Point to local assets so binaries find resources without installation
              export NOCTALIA_ASSETS_DIR="$PWD/assets"

              echo "🌙 Noctalia dev-shell | 'just --list' to see available tasks"
            '';
          };
        };
    };
}
