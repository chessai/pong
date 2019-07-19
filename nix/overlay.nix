{ profiling, haddocks }:

self: super:

with rec {
  inherit (super) lib;

  hlib = super.haskell.lib;

  primitiveOverlaySrc = super.fetchFromGitHub {
    owner = "haskell-primitive";
    repo = "primitive-overlay";
    rev = "a9d88e96b17d5cd7f49048dc678d98db05ad00d0";
    sha256 = "1r5v7zlgldqj2kf6bnnykl5ml09mfzp03kp38xwv2jlzyvmcdagh";
  };

  primitiveOverlay = import primitiveOverlaySrc {
    inherit hlib;
    fetchFromGitHub = super.fetchFromGitHub;
  };

  chessaiOverlaySrc = super.fetchFromGitHub {
    owner = "chessai";
    repo = "overlays";
    rev = "2fa3709044842cd9aa171a31cf8edb6580265c7d";
    sha256 = "0iqhyj24r3q5iz3v8w79a6lzsv4zjpcr61kpnd0wx68gfvnszjx6";
  };

  buildMainOverlay = import "${chessaiOverlaySrc}/buildMain.nix" {
    inherit hlib profiling haddocks;
  };

  c2nOverlay = import "${chessaiOverlaySrc}/c2n.nix" {
    inherit lib hlib;
  };

  networkingOverlay = import "${chessaiOverlaySrc}/networking.nix" {
    inherit hlib;
    fetchFromGitHub = super.fetchFromGitHub;
  };

  mainOverlay = hself: hsuper: {
    pong = hsuper.buildMain "pong" ../.;

    country = hlib.doJailbreak hsuper.country;

    semirings = hsuper.c2n {
      name = "semirings";
      rawPath = super.fetchFromGitHub {
        owner = "chessai";
        repo = "semirings";
        rev = "cf00ccfa25ebf62ff309958bc27185e1d45cc10a";
        sha256 = "0wiy98a6gbj19gb4p6hgb562vzj0r7yrvcdfqwwjy437jw955wsz";
      };
      apply = [ ];
    };

    chronos = hsuper.c2n {
      name = "chronos";
      rawPath = super.fetchFromGitHub {
        owner = "andrewthad";
        repo = "chronos";
        rev = "af0a36bfd8633b859aa0ae7ebc65eebf01125606";
        sha256 = "0zk1wni83dvfl2ikgak59cy0m1mfslh88iibc990qx3jrx3m0mzg";
      };
      apply = [ ];
    };

    quickcheck-classes = hsuper.c2n {
      name = "quickcheck-classes";
      rawPath = super.fetchFromGitHub {
        owner = "andrewthad";
        repo   = "quickcheck-classes";
        rev = "139a00d83e37c11e4a2d38eee63d6004782758ad";
        sha256 = "1v3xa0n30rrpk8yqa71mip1ns1zb59nvgca52xr65fwlh39403dd";
      };
      apply = [ hlib.doJailbreak hlib.dontCheck ];
    };

    hedgehog = hsuper.hedgehog_1_0;

    optparse-applicative = hsuper.c2n {
      name = "optparse-applicative";
      rawPath = super.fetchFromGitHub {
        owner = "pcapriotti";
        repo = "optparse-applicative";
        rev = "5478fc16cbd3384c19e17348a17991896c724a3c";
        sha256 = "1iaxlmgns285x3wzgqps9ap2fg4dk1k36vcnwvi3x8s64svk2mh0";
      };
      apply = [ hlib.dontCheck ];
    };

  };

  composeOverlayList = lib.foldl' lib.composeExtensions (_: _: {});

  overlay = composeOverlayList [
    c2nOverlay
    buildMainOverlay
    primitiveOverlay
    networkingOverlay
    mainOverlay
  ];

};

{
  haskell = super.haskell // {
    packages = super.haskell.packages // {
      ghc865 = (super.haskell.packages.ghc865.override {
        overrides = super.lib.composeExtensions
          (super.haskell.packageOverrides or (self: super: {}))
          overlay;
      });
    };
  };

}
