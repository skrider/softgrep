{ }:
let
    pkgs = import ../../nixpkgs {};
in
pkgs.mkShell {
  buildInputs = with pkgs; [
    # basic
    gnumake
    git
    which
    # languages
    go
    protobuf
    python310
    python3Packages.pip
    # do stuff with files that are in the git tree
    fd
  ];
  shellHook = ''
eval "$(direnv hook bash)"
echo nixpgks version: ${pkgs.lib.version}
export SOFTGREP_NIX_CC_LIB="${pkgs.python310.stdenv.cc.cc.lib}/lib"
  '';
}
