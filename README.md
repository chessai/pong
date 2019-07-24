pong
====

Pinging utility in GHC Haskell

## Usage
```
Usage: pong COMMAND

Available options:
  -h,--help                Show this help text

Available commands:
  host                     One ICMP echo request to a single host
  hosts                    One ICMP echo request to each argument host
  range                    One ICMP echo request to each host in range
  multihosts               Multiple ICMP echo requests to each argument host
  multirange               Multiple ICMP echo requests to each host in range
  blast                    Stress-test a host.
```

## Compiling

### Linux (non-NixOS)
```
cabal new-build
```

Add the CAP_NET_RAW capability to the executable and ping away.

### NixOS
add the following to your system configuration:

```
let pongSrc = builtins.fetchTarball https://github.com/chessai/pong/archive/master.tar.gz
in imports = [
    ("${pongSrc}/module.nix")
  ];
```

This will add pong to your systemPackages, giving it the CAP_NET_RAW capability, so that it can open raw sockets in order to ping things.

### Mac
Might work with cabal new-build.

### Windows
Nope

