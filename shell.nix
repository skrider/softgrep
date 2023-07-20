{ }:
let
    pkgs = import ../../nixpkgs {};
    mkKops = pkgs.mkKops;
    kopsPatch = mkKops rec {
        version = "1.26.4";
        sha256 = "1jfihw41cjydfq27qybdvwns7ip5n9yrgfpqwjph0jfqia91lz3l";
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
