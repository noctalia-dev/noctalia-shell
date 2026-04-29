{ pkgs, noctalia }:

pkgs.mkShell {
  inputsFrom = [ noctalia ];
  
  buildInputs = with pkgs; [
    just
    clang-tools
    gdb
  ];

  shellHook = ''
    echo "Noctalia development environment"
    echo ""
    echo "Available commands:"
    echo "  just configure       - Configure debug build"
    echo "  just build           - Build debug"
    echo "  just run             - Run debug build"
    echo "  just configure release - Configure release build"
    echo "  just build release   - Build release"
    echo "  just run release     - Run release build"
    echo ""
    echo "Note: Use 'just build' instead of 'nix build' due to sdbus-c++ API compatibility"
  '';
}
