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
  };
  pre-commit.hooks = {
    gofmt.enable = true;
    golangci-lint.enable = true;
    govet.enable = true;
    gotest.enable = true;
    hadolint.enable = true;
    mixed-line-endings.enable = true;
    mkdocs-linkcheck.enable = true;
    end-of-file-fixer.enable = true;
    check-symlinks.enable = true;
    check-merge-conflicts.enable = true;
    check-added-large-files.enable = true;
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
