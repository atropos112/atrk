{
  pkgs,
  config,
  lib,
  ...
}: {
  packages = with pkgs; [
    # Testing
    kind
    ginkgo

    # Docs
    mdbook
    mdbook-mermaid
    mdbook-admonish
    mdbook-linkcheck
    mdbook-toc

    # Other
    kubectl
    air
    kubebuilder
    kubernetes-controller-tools
    kustomize
    process-compose
  ];

  scripts = {
    kind-start = {
      exec = ''
        if ! ${pkgs.kubectl}/bin/kubectl config get-clusters | grep -q "atrk"; then
            ${pkgs.kind}/bin/kind create cluster --config $DEVENV_ROOT/kind/config.yaml --name atrk --kubeconfig $DEVENV_ROOT/kind/kubeconfig.yaml
            ${pkgs.kubectl}/bin/kubectl cluster-info
        fi
      '';
      description = "Start the kind cluster";
    };
    kind-setup = {
      exec = ''
        # Start if not started already
        kind-start

        # Install the CRDs
        ${pkgs.kubernetes-controller-tools}/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
        ${pkgs.kubernetes-controller-tools}/bin/controller-gen rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases
        ${pkgs.kustomize}/bin/kustomize build config/crd | ${pkgs.kubectl}/bin/kubectl apply -f -

        # Do cert magic
        make-webhook-cert-work
      '';
      description = "Setup the kind cluster with the CRDs, generated code etc.";
    };

    kind-delete = {
      exec = ''
        ${pkgs.kind}/bin/kind delete cluster --name atrk
      '';
      description = "Stop the kind cluster";
    };

    run-docs = {
      exec = ''
        cd $DEVENV_ROOT
        ${pkgs.mdbook}/bin/mdbook serve --hostname 0.0.0.0
        cd -
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
    make-webhook-cert-work = {
      exec = ''
        # Define the directory and file paths
        DIR="''${TMPDIR:-/tmp}/k8s-webhook-server/serving-certs"

        # Check if the directory exists, if not, create it
        if [ ! -d "$DIR" ]; then
        	mkdir -p "$DIR"
        	echo "Created directory: $DIR"
        fi

        ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$DIR/tls.key" \
            -out "$DIR/tls.crt" \
            -config "$DEVENV_ROOT/kind/cert.conf"

        CA_BUNDLE=$(base64 -w0 "$DIR/tls.crt")

        cat $DEVENV_ROOT/config/webhook/manifests.yaml | ${pkgs.yq}/bin/yq -r '
          .webhooks[0].clientConfig = {
            "url": "https://giant:9443/validate-atro-xyz-v1alpha1-app",
            "caBundle": "'"$CA_BUNDLE"'"
          } |
          .webhooks[1].clientConfig = {
            "url": "https://giant:9443/validate-atro-xyz-v1alpha1-appbase",
            "caBundle": "'"$CA_BUNDLE"'"
          }
        ' | ${pkgs.kubectl}/bin/kubectl apply -f -

      '';
      description = "Generate a self-signed certificate for the webhook server";
    };
    help = {
      exec = ''
        echo
        echo 🦾 Useful project scripts:
        echo 🦾
        ${pkgs.gnused}/bin/sed -e 's| |••|g' -e 's|=| |' <<EOF | ${pkgs.util-linuxMinimal}/bin/column -t | ${pkgs.gnused}/bin/sed -e 's|^|🦾 |' -e 's|••| |g'
        ${lib.generators.toKeyValue {} (lib.mapAttrs (_: value: value.description) config.scripts)}
        EOF
        echo

      '';
      description = "Show this help message";
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

  languages.go = {
    enable = true;
    enableHardeningWorkaround = true;
    package = pkgs.go_1_23;
  };

  process-managers = {
    process-compose = {
      enable = true;
      package = pkgs.process-compose;
      settings = {
        environment = [
          "GOPATH=$HOME/.go"
        ];
        processes = {
          docs = {
            command = "run-docs";
          };
          atrk = {
            command = "start";
            working_dir = "$DEVENV_ROOT";
            depends_on = {
              cluster-setup.condition = "process_completed";
            };
          };
        };
      };
    };
  };

  processes = {
    cluster-setup.exec = "kind-setup";
  };

  enterShell = ''
    export KUBECONFIG=$DEVENV_ROOT/kind/kubeconfig.yaml
    export GOPATH=$HOME/.go # Not using the .devenv/state path as it will clash with the go tools such as controller-gen
    echo
    echo 🦾 Useful project scripts:
    echo 🦾
    ${pkgs.gnused}/bin/sed -e 's| |••|g' -e 's|=| |' <<EOF | ${pkgs.util-linuxMinimal}/bin/column -t | ${pkgs.gnused}/bin/sed -e 's|^|🦾 |' -e 's|••| |g'
    ${lib.generators.toKeyValue {} (lib.mapAttrs (_: value: value.description) config.scripts)}
    EOF
    echo
  '';
}
