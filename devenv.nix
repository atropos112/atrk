{
  pkgs,
  config,
  lib,
  ...
}: {
  packages = with pkgs; [
    kind
    kubectl
    air
    mdbook
    mdbook-mermaid
  ];

  scripts = {
    kind-start = {
      exec = ''
        if ! kubectl config get-clusters | grep -q "atrk"; then
            kind create cluster --config $DEVENV_ROOT/kind/config.yaml --name atrk --kubeconfig $DEVENV_ROOT/kind/kubeconfig.yaml
        fi
      '';
      description = "Start the kind cluster";
    };

    kind-stop = {
      exec = ''
        kind delete cluster --name atrk
      '';
      description = "Stop the kind cluster";
    };

    run-docs = {
      exec = ''
        mkdocs serve
      '';
      description = "Run the documentation server";
    };
    start = {
      exec = ''
        cd $DEVENV_ROOT
        kind-start
        ${pkgs.air}/bin/air
        cd -
      '';
      description = "Start the atrk server and watch for changes";
    };
    make-webhook-cert = {
      exec = ''
        # Define the directory and file paths
        DIR="/tmp/k8s-webhook-server/serving-certs"
        CRT_FILE="$DIR/tls.crt"
        KEY_FILE="$DIR/tls.key"

        # Check if the directory exists, if not, create it
        if [ ! -d "$DIR" ]; then
            mkdir -p "$DIR"
            echo "Created directory: $DIR"
        fi

        # Check if the tls.crt file exists
        if [ ! -f "$CRT_FILE" ]; then
            # Generate a private key
            openssl genrsa -out "$KEY_FILE" 2048
            echo "Generated private key: $KEY_FILE"

            # Create a self-signed certificate
            openssl req -new -x509 -key "$KEY_FILE" -out "$CRT_FILE" -days 365 -subj "/CN=localhost"
            echo "Generated self-signed certificate: $CRT_FILE"
        else
            echo "Certificate already exists: $CRT_FILE"
        fi
      '';
      description = "Generate a self-signed certificate for the webhook server";
    };
  };
  pre-commit.hooks = {
    gofmt.enable = true;
    golangci-lint.enable = true;
    govet.enable = true;
    gotest.enable = true;
    hadolint.enable = true;
    mixed-line-endings.enable = true;
    end-of-file-fixer.enable = true;
    check-symlinks.enable = true;
    check-merge-conflicts.enable = true;
    actionlint.enable = true;
    revive.enable = true;
    trufflehog.enable = true;
  };

  enterShell = ''
    export KUBECONFIG=$DEVENV_ROOT/kind/kubeconfig.yaml
    echo
    echo 🦾 Useful project scripts:
    echo 🦾
    ${pkgs.gnused}/bin/sed -e 's| |••|g' -e 's|=| |' <<EOF | ${pkgs.util-linuxMinimal}/bin/column -t | ${pkgs.gnused}/bin/sed -e 's|^|🦾 |' -e 's|••| |g'
    ${lib.generators.toKeyValue {} (lib.mapAttrs (_: value: value.description) config.scripts)}
    EOF
    echo
  '';
}
