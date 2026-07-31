{
  description = "A sleek, customizable desktop shell crafted for Wayland.";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

    # Photosensitivity-filtered Milkdrop presets pack for the optional
    # livepaper visualizer. Its default package output is a pre-built,
    # brightness/strobe-filtered preset pack.
    presets-photosensitive-filtered.url = "github:weissi1994/presets-photosensitive-filtered";
  };

  outputs =
    {
      self,
      nixpkgs,
      presets-photosensitive-filtered,
    }:
    let
      inherit (nixpkgs.lib) genAttrs getExe warn;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forEachSystem =
        perSystem:
        genAttrs systems (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          perSystem { inherit pkgs system; }
        );
    in
    {
      overlays.default = final: prev: {
        noctalia = final.callPackage ./nix/package.nix { };
      };

      packages = forEachSystem (
        { pkgs, ... }:
        rec {
          default = pkgs.callPackage ./nix/package.nix { };

          # Trimmed Milkdrop presets pack for the optional livepaper
          # visualizer. nix/filter-presets.py rejects .milk files whose code
          # paints overly bright frames or rapid strobes. Exposed as its own
          # output so it can be built and staged independently of a full
          # home-manager rollout (e.g. `nix build .#presets`).
          presets = presets-photosensitive-filtered.packages.${pkgs.stdenv.hostPlatform.system}.default;

          # DEPRECATED: identical to `default`; kept for compat, warns on use.
          cuda = warn
            "noctalia: the `.#cuda` package output is deprecated and now identical to `.#default` (autoAddDriverRunpath is always applied); switch to `.#default`. This alias will be removed in the future."
            default;
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
            program = getExe self.packages.${system}.default;
          };
        }
      );

      homeModules.default =
        { pkgs, lib, ... }:
        {
          imports = [ ./nix/home-module.nix ];
          programs.noctalia.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          programs.noctalia.wallpaper.live_paper.presetsSource =
            lib.mkDefault
              presets-photosensitive-filtered.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };

      hjemModules.default =
        { pkgs, lib, ... }:
        {
          imports = [ ./nix/hjem-module.nix ];
          programs.noctalia.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };

      nixosModules.default =
        { pkgs, lib, ... }:
        {
          imports = [ ./nix/nixos-module.nix ];
          programs.noctalia.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
    };
}
