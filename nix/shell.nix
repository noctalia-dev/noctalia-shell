{
  quickshell,
  callPackage,
  nixfmt,
  statix,
  deadnix,
  shfmt,
  shellcheck,
  jsonfmt,
  lefthook,
  kdePackages,
  mkShellNoCC,
}:
let
  runtimeDeps = callPackage ./runtime-deps.nix { };
in
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
  ] ++ runtimeDeps;
}
