{ }:
let
    pkgs = import ../../nixpkgs {};
in
pkgs.mkShell {
    buildInputs = with pkgs; [
        gnumake
        git
        which
        go
        protobuf
        python310
        python3Packages.pip
        fd
        jq
        yq-go
        envsubst
        grpcurl
        docker
        minikube
        kubernetes-helm
        k9s
        kubectl
        kubectx
        eksctl
        awscli2
        terraform
    ];
    shellHook = ''
echo nixpgks version: ${pkgs.lib.version}
export NIX_LD_LIB=${pkgs.python310.stdenv.cc.cc.lib}/lib
export AWS_DEFAULT_REGION=us-west-2
export PATH="$PATH:$(pwd)/scripts"
    '';
}
