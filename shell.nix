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
    # manipulate json
    jq
    # deployment
    docker
    minikube
    kubernetes-helm
    k9s
    kubectl
    eksctl
    awscli2
  ];
  shellHook = ''
echo nixpgks version: ${pkgs.lib.version}
export NIX_LD_LIB=${pkgs.python310.stdenv.cc.cc.lib}/lib
export AWS_DEFAULT_REGION=us-west-2
source venv/bin/activate
  '';
}
