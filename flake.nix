{
  description = "Noctalia - A lightweight Wayland shell and bar";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSystem = perSystem:
        lib.genAttrs systems (
          system: let
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
        { pkgs, ... }: {
          default = pkgs.callPackage ./nix/package.nix { };
        }
      );

      devShells = forEachSystem (
        { pkgs, system }: {
          default = pkgs.callPackage ./nix/devshell.nix {
            noctalia = self.packages.${system}.default;
          };
        }
      );

      apps = forEachSystem (
        { pkgs, system }: {
          default = {
            type = "app";
            program = lib.getExe self.packages.${system}.default;
          };
        }
      );
    };
}
