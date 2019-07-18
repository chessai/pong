{ profiling, haddocks }:

self: super:

with rec {
  inherit (super) lib;

  hlib = super.haskell.lib;

  primitiveOverlaySrc = super.fetchFromGitHub {
    owner = "haskell-primitive";
    repo = "primitive-overlay";
    rev = "a5279fdb180a7c2a9e9d5eef030c2a0c12303f1f";
    sha256 = "1jj2f5n64bhl9yk86ybkbq3kl9d58cipp989n24z3lv8g5g6sbxw";
  };

  primitiveOverlay = import primitiveOverlaySrc {
    inherit hlib;
    fetchFromGitHub = super.fetchFromGitHub;
  };

  # This function removes any cruft not relevant to our Haskell builds.
  #
  # If something irrelevant to our build is not removed by this function, and
  # you modify that file, Nix will rebuild the derivation even though nothing
  # that would affect the output has changed.
  #
  # The `excludePred` argument is a function that can be used to filter out more
  # files on a package-by-package basis.
  # The `includePred` argument is a function that can be used to include files
  # that this function would normally filter out.
  clean = (
    { path,
      excludePred ? (name: type: false),
      includePred ? (name: type: false)
    }:
    if lib.canCleanSource path
    then lib.cleanSourceWith {
           filter = name: type: (includePred name type) || !(
             with rec {
               baseName     = baseNameOf (toString name);
               isFile       = (type == "regular");
               isLink       = (type == "symlink");
               isDir        = (type == "directory");
               isUnknown    = (type == "unknown");
               isNamed      = str: (baseName == str);
               hasExtension = ext: (lib.hasSuffix ext baseName);
               beginsWith   = pre: (lib.hasPrefix pre baseName);
               matches      = regex: (builtins.match regex baseName != null);
             };

             lib.any (lib.all (x: x)) [
               # Each element of this list is a list of booleans, which should be
               # thought of as a "predicate" on paths; the predicate is true if the
               # list is composed entirely of true values.
               #
               # If any of these predicates is true, then the path will not be
               # included in the source used by the Nix build.
               #
               # Remember to use parentheses around elements of a list;
               # `[ f x ]`   is a heterogeneous list with two elements,
               # `[ (f x) ]` is a homogeneous list with one element.
               # Knowing the difference might save your life.
               [ (excludePred name type) ]
               [ isUnknown ]
               [ isDir (isNamed "dist") ]
               [ isDir (isNamed "dist-newstyle") ]
               [ isDir (isNamed  "run") ]
               [ (isFile || isLink) (hasExtension ".nix") ]
               [ (beginsWith ".ghc") ]
               [ (hasExtension ".sh") ]
               [ (hasExtension ".txt") ]
             ]);
           src = lib.cleanSource path;
         }
    else path);

  mainOverlay = hself: hsuper: {
    callC2N = (
      { name,
        path                  ? (throw "callC2N requires path argument!"),
        rawPath               ? (clean { inherit path; }),
        relativePath          ? null,
        args                  ? {},
        apply                 ? [],
        extraCabal2nixOptions ? []
      }:

      with rec {
        filter = p: type: (
          (super.lib.hasSuffix "${name}.cabal" p)
          || (baseNameOf p == "package.yaml"));
        expr = hsuper.haskellSrc2nix {
          inherit name;
          extraCabal2nixOptions = self.lib.concatStringsSep " " (
            (if relativePath == null then [] else ["--subpath" relativePath])
            ++ extraCabal2nixOptions);
          src = if super.lib.canCleanSource rawPath
                then super.lib.cleanSourceWith { src = rawPath; inherit filter; }
                else rawPath;
        };
        compose = f: g: x: f (g x);
        composeList = x: lib.foldl' compose lib.id x;
      };

      composeList apply
      (hlib.overrideCabal
       (hself.callPackage expr args)
       (orig: { src = rawPath; }))
    );

    pong = hself.callC2N {
      name = "pong";
      path = ../.;
      apply = [ hlib.dontCheck ]
        ++ ( if profiling
             then [ hlib.enableLibraryProfiling hlib.enableExecutableProfiling ]
             else [ hlib.disableLibraryProfiling hlib.disableExecutableProfiling ]
           )
        ++ ( if haddocks
             then [ hlib.doHaddock ]
             else [ hlib.dontHaddock ]
           );
    };

    ping = hself.callC2N {
      name = "ping";
      rawPath = super.fetchFromGitHub {
        owner = "andrewthad";
        repo = "ping";
        rev = "82229a41507732049ff90e1cc3abff69be26540f";
        sha256 = "1n0apsinwj52c1m17hjd91sxp2r6m7sn185ykkzfszb7xrm0xskg";
      };
      apply = [ ];
    };

    sockets = hlib.overrideCabal (hself.callC2N {
      name = "sockets";
      rawPath = super.fetchFromGitHub {
        owner = "andrewthad";
        repo = "sockets";
        rev = "58b5bfc54c3ee77984871bec91ad5f08c46fa6eb";
        sha256 = "1sdpaxz65y565rzrsnprj9nr4lbmzylqpkraps4n9f26cb2f0i1s";
      };
      apply = [ hlib.dontHaddock ];
    }) (old : {
      configureFlags = [
        # GHC cannot perform multithreaded backpackified typechecking
        # Nix's generic haskell builder invokes ghc with `j$NIX_BUILD_CORES`
        # by default. Anything other than 1 behind that value results in
        # GHC giving up when attempting to compile `sockets`.
        "--ghc-option=-j1"
        "-f+verbose-errors"
      ];
    });

    posix-api = hself.callC2N {
      name = "posix-api";
      rawPath = super.fetchFromGitHub {
        owner = "andrewthad";
        repo = "posix-api";
        rev = "6344f841b969cb70195e49093be1504b4a84f7c5";
        sha256 = "09d025jfiaznwzsr9fny4ncb51nh5vbhj5nwb1y2y6w8ivgs717r";
      };
      apply = [ hlib.dontCheck ];
    };

    country = hlib.doJailbreak hsuper.country;

    semirings = hself.callC2N {
      name = "semirings";
      rawPath = super.fetchFromGitHub {
        owner = "chessai";
        repo = "semirings";
        rev = "cf00ccfa25ebf62ff309958bc27185e1d45cc10a";
        sha256 = "0wiy98a6gbj19gb4p6hgb562vzj0r7yrvcdfqwwjy437jw955wsz";
      };
      apply = [ hlib.doJailbreak hlib.dontHaddock hlib.dontCheck hlib.dontBenchmark ];
    };

    error-codes = hself.callC2N {
      name = "error-codes";
      rawPath = super.fetchFromGitHub {
        owner = "andrewthad";
        repo = "error-codes";
        rev = "5eb520f475285eeed17fe33f4bac5929104657a0";
        sha256 = "0shcvsyykbpwjsd9nwnyxkp298wmfpa7v2h8vw1clhka2xsw2c86";
      };
      apply = [ ];
    };

    ip = hself.callC2N {
      name = "ip";
      rawPath = super.fetchFromGitHub {
        owner = "andrewthad";
        repo = "haskell-ip";
        rev = "2fe1a38d1bf2155cf068ac3b7e08fa7319d4231c";
        sha256 = "13z01jryfkfj9z7d45nsb55v6798gv9dqqrqw5wxymzywmhqyc4m";
      };
      apply = [ ];
    };

    chronos = hself.callC2N {
      name = "chronos";
      rawPath = super.fetchFromGitHub {
        owner = "andrewthad";
        repo = "chronos";
        rev = "af0a36bfd8633b859aa0ae7ebc65eebf01125606";
        sha256 = "0zk1wni83dvfl2ikgak59cy0m1mfslh88iibc990qx3jrx3m0mzg";
      };
      apply = [ ];
    };

    wide-word = hself.callC2N {
      name = "wide-word";
      rawPath = super.fetchFromGitHub {
        owner = "erikd";
        repo = "wide-word";
        rev = "f216c223c6ae4fb3854803c39f1244686cb06353";
        sha256 = "1bn6ikqvhbsh6j6qrvcdl9avcgp2128an0mjv7ckspxanx2avpip";
      };
      apply = [ ];
    };

    quickcheck-classes = hself.callC2N {
      name = "quickcheck-classes";
      rawPath = super.fetchFromGitHub {
        owner = "andrewthad";
        repo   = "quickcheck-classes";
        rev = "139a00d83e37c11e4a2d38eee63d6004782758ad";
        sha256 = "1v3xa0n30rrpk8yqa71mip1ns1zb59nvgca52xr65fwlh39403dd";
      };
      apply = [ hlib.doJailbreak hlib.dontCheck ];
    };

    optparse-applicative = hself.callC2N {
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
    primitiveOverlay
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
