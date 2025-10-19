{
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    treefmt = {
      enableDefaultExcludes = true;
      flakeCheck = true;
      flakeFormatter = true;

      programs = {
        alejandra = {
          enable = true;
          priority = 3;
          includes = [
            "*.nix"
          ];
        };

        deadnix = {
          enable = true;
          priority = 3;
          includes = [
            "*.nix"
          ];
        };

        statix = {
          enable = true;
          priority = 3;
          includes = [
            "*.nix"
          ];
        };

        shfmt = {
          enable = true;
          priority = 1;
          indent_size = 3;
          includes = [
            "*.sh"
          ];
        };

        shellcheck = {
          enable = true;
          priority = 1;
          includes = [
            "*.sh"
          ];
        };

        jsonfmt = {
          enable = true;
          priority = 2;
          includes = [
            "*.json"
            "*.jsonc"
          ];
        };
      };

      settings = {
        global.excludes = [
          "*.qmlls.ini"
          ".zed/"
        ];

        formatter = {
          "qmlfmt" = {
            command = ''${lib.getExe' pkgs.kdePackages.qtdeclarative "qmlformat"}'';
            includes = [
              "*.qml"
            ];
          };
        };
      };
    };
  };
}
