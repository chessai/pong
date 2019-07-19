let
  fetchNixpkgs = import ./fetchNixpkgs.nix;

  nixpkgs = fetchNixpkgs {
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "69f2836c1bbfbd94322ec740ded789bc6ec3a440";
    sha256 = "0r9iirlj1cylbngy0jlh6qnvxz8vzdxgbyw5ncjynbw0h4qqfzq8";
  };

in
  nixpkgs
