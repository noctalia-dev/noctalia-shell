{
  description = "Noctalia - A lightweight Wayland shell and bar";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "noctalia";
          version = "5.0.0";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            meson
            ninja
            pkg-config
            wayland-scanner
          ];

          buildInputs = with pkgs; [
            wayland
            wayland-protocols
            libGL
            libglvnd
            freetype
            fontconfig
            cairo
            pango
            libxkbcommon
            sdbus-cpp_2
            systemd
            pipewire
            pam
            curl
            libwebp
          ];

          mesonBuildType = "release";
          
          dontUseMesonConfigure = true;
          
          configurePhase = ''
            runHook preConfigure
            meson setup build --prefix=$out --buildtype=release
            runHook postConfigure
          '';
          
          buildPhase = ''
            runHook preBuild
            meson compile -C build
            runHook postBuild
          '';
          
          installPhase = ''
            runHook preInstall
            meson install -C build
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "A lightweight Wayland shell and bar built directly on Wayland + OpenGL ES";
            homepage = "https://github.com/anomalyco/noctalia-shell";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "noctalia";
          };
        };

        # Development shell with all dependencies
        # Use this for development: nix develop
        devShells.default = pkgs.mkShell {
          inputsFrom = [ self.packages.${system}.default ];
          
          buildInputs = with pkgs; [
            just
            clang-tools
            gdb
          ];

          shellHook = ''
            echo "Noctalia development environment"
            echo ""
            echo "Available commands:"
            echo "  just configure       - Configure debug build"
            echo "  just build           - Build debug"
            echo "  just run             - Run debug build"
            echo "  just configure release - Configure release build"
            echo "  just build release   - Build release"
            echo "  just run release     - Run release build"
            echo ""
            echo "Note: Use 'just build' instead of 'nix build' due to sdbus-c++ API compatibility"
          '';
        };

        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/noctalia";
        };
      }
    );
}
