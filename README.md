# vsc

vsc is a [nix](https://nixos.org/nix/) [flake](https://github.com/NixOS/rfcs/pull/49) that wraps [VSCodium](https://github.com/VSCodium/VScodium) in an environment providing recent versions of other development tools like [Go](https://golang.org) and [Rust](https://rust-lang.org). It can be run via 

```bash
`nix app git+https://github.com/mstone/vsc
```

with recent versions of `nix`.
