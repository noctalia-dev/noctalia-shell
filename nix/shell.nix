{
  pkgs,
  quickshell,
  alejandra,
  statix,
  deadnix,
  shfmt,
  shellcheck,
  jsonfmt,
  lefthook,
  kdePackages,
  mkShellNoCC,
}:
mkShellNoCC {
  #it's faster than mkDerivation / mkShell
  packages = [
    quickshell

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
    kdePackages.qtdeclarative # qmlfmt, qmllint, qmlls and etc; Qt6

    (pkgs.callPackage ./noctalia-live-devel.nix {inherit pkgs;})
    (pkgs.callPackage ./qs-noctalia.nix {inherit pkgs;})
  ];
}
