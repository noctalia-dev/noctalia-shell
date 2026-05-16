{
  description = "Noctalia - A lightweight Wayland shell and bar";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

    # Milkdrop presets pack used by the optional livepaper visualizer.
    # Wrapped through nix/filter-presets.py at build time to drop overly
    # bright / strobing presets.
    presets-cream-of-the-crop = {
      url = "github:projectM-visualizer/presets-cream-of-the-crop";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      presets-cream-of-the-crop,
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forEachSystem =
        perSystem:
        lib.genAttrs systems (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          perSystem { inherit pkgs system; }
        );

      mkDate =
        longDate:
        nixpkgs.lib.concatStringsSep "-" [
          (builtins.substring 0 4 longDate)
          (builtins.substring 4 2 longDate)
          (builtins.substring 6 2 longDate)
        ];

      shortRev = self.shortRev or "dirty";
      version = mkDate (self.lastModifiedDate or "19700101") + "_" + shortRev;
    in
    {
      overlays.default = final: prev: {
        noctalia = final.callPackage ./nix/package.nix { inherit version shortRev; };
      };

      packages = forEachSystem (
        { pkgs, ... }:
        {
          default = pkgs.callPackage ./nix/package.nix { inherit version shortRev; };

          # Trimmed Milkdrop presets pack for the optional livepaper
          # visualizer. nix/filter-presets.py rejects .milk files whose code
          # paints overly bright frames or rapid strobes. Exposed as its own
          # output so it can be built and staged independently of a full
          # home-manager rollout (e.g. `nix build .#presets`).
          presets = pkgs.runCommand "presets-filtered" { } ''
            mkdir -p "$out"
            cp -r --no-preserve=mode ${presets-cream-of-the-crop}/* "$out/"
            ${pkgs.python3}/bin/python3 ${./nix/filter-presets.py} "$out"
          '';
        }
      );

      devShells = forEachSystem (
        { pkgs, system }:
        {
          default = pkgs.callPackage ./nix/devshell.nix {
            noctalia = self.packages.${system}.default;
          };
        }
      );

      apps = forEachSystem (
        { system, ... }:
        {
          default = {
            type = "app";
            program = lib.getExe self.packages.${system}.default;
          };
        }
      );

      homeModules.default =
        { pkgs, lib, ... }:
        {
          imports = [ ./nix/home-module.nix ];
          programs.noctalia.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          programs.noctalia.wallpaper.live_paper.presetsSource =
            lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.presets;
        };
    };
}
