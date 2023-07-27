{ }:
let
    pkgs = import ../../nixpkgs {};
    mkKops = pkgs.mkKops;
    kopsPatch = mkKops rec {
        version = "1.27.0";
        sha256 = "1nmfman699rh80r5pslxqicnd5zsbdsb2nk5crbwbg7zwjl9v4sw";
        rev = "v${version}";
    };
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
        kopsPatch
    ];
    shellHook = ''
echo nixpgks version: ${pkgs.lib.version}
export NIX_LD_LIB=${pkgs.python310.stdenv.cc.cc.lib}/lib
export AWS_DEFAULT_REGION=us-west-2
export PATH="$PATH:$(pwd)/scripts"
    '';
}
