{
  description = "Noctalia shell - a Wayland desktop shell built with Quickshell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    systems,
    quickshell,
    ...
  }: let
    eachSystem = nixpkgs.lib.genAttrs (import systems);
  in {
    formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

    packages = eachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.callPackage ./nix/package.nix {
          version = self.rev or self.dirtyRev or "dirty";
          quickshell = quickshell.packages.${system}.default.override {
            withX11 = false;
            withI3 = true;
          };
        };
      }
    );

    defaultPackage = eachSystem (system: self.packages.${system}.default);

    devShells = eachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        default = pkgs.callPackage ./shell.nix {};
      }
    );

    homeModules.default = {
      pkgs,
      lib,
      ...
    }: {
      imports = [./nix/home-module.nix];
      programs.noctalia-shell.package = lib.mkDefault self.packages.${pkgs.system}.default;
      programs.noctalia-shell.app2unit.package =
        lib.mkDefault
        nixpkgs.legacyPackages.${pkgs.system}.app2unit;
    };

    nixosModules.default = {
      pkgs,
      lib,
      ...
    }: {
      imports = [./nix/nixos-module.nix];
      services.noctalia-shell.package = lib.mkDefault self.packages.${pkgs.system}.default;
    };
  };
}
