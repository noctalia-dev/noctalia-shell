let
  inherit (builtins)
    fromJSON
    readFile
    substring
    pathExists
    ;

  lock = fromJSON (readFile ./flake.lock);
  namedNode = lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
  nixpkgs = fetchTarball {
    inherit (namedNode) url;
    sha256 = namedNode.narHash;
  };
in
{
  pkgs ? import nixpkgs { },
}:
let
  inherit (pkgs.lib) cleanSource mkDefault concatStringsSep;

  # Taken from flake-compat
  src =
    let
      tryFetchGit =
        if (pathExists ./.git) then
          let
            res = fetchGit ./.;
          in
          if res.rev == "0000000000000000000000000000000000000000" then
            removeAttrs res [
              "rev"
              "shortRev"
            ]
          else
            res
        else
          {
            outPath = ./.;
          };

    in
    {
      lastModified = 0;
      lastModifiedDate = "19700101";
    }
    // tryFetchGit;

  mkDate =
    longDate:
    concatStringsSep "-" [
      (substring 0 4 longDate)
      (substring 4 2 longDate)
      (substring 6 2 longDate)
    ];

  shortRev = src.shortRev or "dirty";

  package = pkgs.callPackage ./nix/package.nix {
    inherit shortRev;
    version = mkDate (src.lastModifiedDate or "19700101") + "_" + shortRev;
    source = cleanSource src;
  };
in
{
  hjemModule = {
    imports = [ ./nix/hjem-module.nix ];
    programs.noctalia.package = mkDefault package;
    _class = "hjem";
  };

  homeModule = {
    imports = [ ./nix/home-module.nix ];
    programs.noctalia.package = mkDefault package;
    _class = "homeManager";
  };

  inherit package;
}
