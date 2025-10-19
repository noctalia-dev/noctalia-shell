{
  description = "Noctalia shell - a Wayland desktop shell built with Quickshell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
  # more elegant than `eachSystem f:`, way better than utils, and expandable
    flake-parts.lib.mkFlake {
      inherit
        inputs
        ;
    } {
      imports = [
        # self.homeModules.default;
        inputs.home-manager.flakeModules.home-manager
        ./nix/home-module.nix

        # self.nixosModules.default;
        ./nix/nixos-module.nix

        # one-for-all formatter;
        inputs.treefmt-nix.flakeModule
        ./nix/treefmt.nix
      ];

      systems = [
        # any other system could be added here
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake = {self', ...}: {
        nixosModules.noctalia-shell = self'.nixosModules.default;
        homeModules.noctalia-shell = self'.homeModules.default;
      };

      perSystem = {
        self',
        pkgs,
        system,
        ...
      }: {
        # in case of manual formatting / linitng
        # or to extend things.
        # devShell is a native development env,
        # supported by direnv, devenv, and nix
        # itself. just use `nix develop --command <shell>`
        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              # nix
              alejandra # formatter
              statix # linter
              deadnix # linter

              # shell
              shfmt # formatter
              shellcheck # linter

              # json
              jsonfmt # formatter

              # CoC
              lefthook # githooks
              kdePackages.qtdeclarative # qmlfmt, qmllin and etc; Qt6
            ];
          };
        };

        # this way packages are wrapped, and extandable!
        packages = {
          noctalia-shell = self'.packages.default;
          default = pkgs.callPackage ./nix/package.nix {
            version = self'.rev or self'.dirtyRev or "dirty";
            quickshell = inputs.quickshell.packages.${system}.default.override {
              withX11 = false;
              withI3 = true;
            };
          };
        };
      };
    };
}
