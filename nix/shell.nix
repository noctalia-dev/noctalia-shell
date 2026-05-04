{
  quickshell,
  nixfmt,
  statix,
  deadnix,
  shfmt,
  shellcheck,
  jsonfmt,
  lefthook,
  lib,
  kdePackages,
  mkShellNoCC,
}:
mkShellNoCC {
  #it's faster than mkDerivation / mkShell
  packages = [
    quickshell

    # nix
    nixfmt # formatter
    statix # linter
    deadnix # linter

    # shell
    shfmt # formatter
    shellcheck # linter

    # json
    jsonfmt # formatter

    # CoC
    lefthook # githooks
    kdePackages.qtdeclarative # qmlfmt, qmllint, qmlls and etc; Qt6
  ];

  env.QML_IMPORT_PATH = lib.makeSearchPathOutput "lib" kdePackages.qtbase.qtQmlPrefix [quickshell kdePackages.qtdeclarative];
}
