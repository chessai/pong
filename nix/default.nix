{ nixpkgs   ? import ./nixpkgs.nix # nix package set we're using
, profiling ? false # Whether or not to enable library profiling (applies to internal deps only)
, haddocks  ? false # Whether or not to enable haddock building (applies to internal deps only)
}:

with rec {
  compiler = "ghc865";

  pkgs = import nixpkgs {
    config = {
      allowUnfree = false;
      allowBroken = false;
    };
    overlays = [
      (import ./overlay.nix { inherit profiling haddocks; })
    ];
  };

  make = name: pkgs.haskell.packages.${compiler}.${name};

  pong = make "pong";

};

rec {
  inherit pkgs;
  inherit nixpkgs;
  inherit pong;
}
