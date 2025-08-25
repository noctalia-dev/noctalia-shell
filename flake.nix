{
  description = "Desktop shell for Caelestia dots";

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
    ...
  } @ inputs: let
    eachSystem = nixpkgs.lib.genAttrs (import systems);
  in {
    formatter = eachSystem (pkgs: pkgs.alejandra);

    packages = eachSystem (system: rec {
      noctalia-shell = nixpkgs.legacyPackages.${system}.callPackage ./nix {
        rev = self.rev or self.dirtyRev;
        quickshell = inputs.quickshell.packages.${system}.default.override {
          withX11 = false;
          withI3 = false;
        };
      };
      default = noctalia-shell;
    });
  };
}
