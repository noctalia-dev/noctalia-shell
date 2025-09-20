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

    packages = eachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      qs = quickshell.packages.${system}.default.override {
        withX11 = false;
        withI3 = false;
      };

      version = self.rev or self.dirtyRev or "dirty";
      src = self;

      runtimeDeps = with pkgs;
        [
          bash
          bluez
          brightnessctl
          cava
          cliphist
          coreutils
          ddcutil
          file
          findutils
          libnotify
          matugen
          networkmanager
          wlsunset
          wl-clipboard
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
          gpu-screen-recorder
        ];

      fontconfig = pkgs.makeFontsConf {
        fontDirectories = [pkgs.roboto pkgs.inter-nerdfont];
      };

      noctalia = pkgs.stdenv.mkDerivation {
        pname = "noctalia-shell";
        inherit version src;

        nativeBuildInputs = [
          pkgs.gcc
          pkgs.makeWrapper
          pkgs.qt6.wrapQtAppsHook
        ];

        buildInputs = [
          qs
          pkgs.xkeyboard_config
          pkgs.qt6.qtbase
        ];

        propagatedBuildInputs = runtimeDeps;

        installPhase = ''
          mkdir -p $out/bin
          mkdir -p $out/share/noctalia-shell
          cp -r ./* $out/share/noctalia-shell

          makeWrapper ${qs}/bin/qs $out/bin/noctalia-shell \
            --prefix PATH : "${pkgs.lib.makeBinPath runtimeDeps}" \
            --set FONTCONFIG_FILE "${fontconfig}" \
            --add-flags "-p $out/share/noctalia-shell"
        '';

        meta = {
          description = "A sleek and minimal desktop shell thoughtfully crafted for Wayland, built with Quickshell.";
          homepage = "https://github.com/noctalia-dev/noctalia-shell";
          license = lib.licenses.mit;
          mainProgram = "noctalia-shell";
        };
      };
    in {
      default = noctalia;
    });

    defaultPackage = eachSystem (system: self.packages.${system}.default);

    nixosModules.default = {
      config,
      pkgs,
      lib,
      ...
    }: let
      system = pkgs.stdenv.hostPlatform.system;
      noctaliaShell = self.packages.${system}.default;
    in {
      options.noctalia.enable = lib.mkEnableOption "Enable the Noctalia Wayland shell";

      config = lib.mkIf config.noctalia.enable {
        environment.systemPackages = [noctaliaShell];
      };
    };
  };
}
