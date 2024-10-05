# Development

The project is developed in Go using Kubebuilder framework and devenv nix shell for development environment.

## Table of Contents

<!-- toc -->

## Kubebuilder setup

Initially the project was created using the following command

```bash
kubebuilder init --plugins go/v4 --domain atro.xyz --owner "Atropos" --project-name atrk --repo github.com/atropos112/atrk
```

Then the APIs were created using the following commands

```bash
kubebuilder create api --kind App --version v1alpha1 --namespaced
kubebuilder create api --kind AppBase --version v1alpha1 --namespaced=false --plural=appbases
```

The plan is to have App be a custom resource that is namespaced, while the AppBase should be cluster scoped henced why AppBase has `--namespaced=false`, I have also added `--pluaral` to AppBase just to be sure but its not really needed.

Having gotten the API the next thing is to get validating webhooks, this I did with

```bash
kubebuilder create webhook --kind AppBase --version v1alpha1 --programmatic-validation
kubebuilder create webhook --kind App --version v1alpha1 --programmatic-validation
```

# Webhook and the certificate

Currently kubebuilder setup creates a ValidatingAdmissionWebhook which is pointing to a service that would exist in the cluster had we deployed the application to the cluster.

This does however introduce a problem, when you start up the go application (in debug mode or normally), the webhook is never called, this is obviously troublesome in terms of local testing.

The solution is not ideal but is best I could think of for now, it comes with some gotchas. `make-webhook-cert-work` devenv command creates a new cert in the expected location `/tmp/k8s-webhook-server/serving-certs/tls.crt`, it does this using `kind/cert.conf` which states some configs and most importantly alt_names.

The command also does a `yq` snipping on the `config/webhook/manifests.yaml` to point to the correct url and use `caBundle`(base64 of the previously generated certificate) it then reapplies it to the cluster so now the webhook validation points to the local machine.

```admonish warning
The downside of this is two-fold:
- Complexity is obviously high
- Currently the cert.conf and devenv snipping of `manifests.yaml` is hardcoded to point to `giant` which is name external tailscale hostname that points to my machine, this is obviously suboptimal as it means you have to replace giant with your tailscale hostname or use ngrok.
```

```admonish todo
Find a better way to handle this connection, maybe some local ngrok setup or something else. Or accept an arg and default to hostname.
```

Either way its now possible to test the webhook locally. And it will "just work" when deployed to the cluster as well.
