{ config, pkgs, ... }:

{
  config = {
    nixpkgs.overlays = [
      (self: super: {
        pong = self.callPackage ./default.nix {};
      })
    ];

    security.wrappers.pong = {
      source = "${pkgs.pong}/bin/pong";
      capabilities = "cap_net_raw+ep";
    };

    environment.systemPackages = [ pkgs.pong ];
  };
}
