/*
Copyright 2024 Atropos.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Package main contains the entrypoint of the controller.
package main

import (
	"crypto/tls"
	"flag"
	"os"

	"go.uber.org/zap/zapcore"
	_ "k8s.io/client-go/plugin/pkg/client/auth"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"
	"sigs.k8s.io/controller-runtime/pkg/webhook"

	atroxyzv1alpha1 "github.com/atropos112/atrk/api/v1alpha1"
	"github.com/atropos112/atrk/internal/controller"
	// +kubebuilder:scaffold:imports
)

var (
	scheme = runtime.NewScheme()

	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	// Schema for Kubernetes objects.
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))

	// Schema for atro.xyz (internal atrk) objects.
	utilruntime.Must(atroxyzv1alpha1.AddToScheme(scheme))

	// +kubebuilder:scaffold:scheme
}

func main() {
	// INFO: Gather the command-line arguments.
	var metricsAddr string
	flag.StringVar(&metricsAddr, "metrics-bind-address", "0.0.0.0:8080", "The address the metrics endpoint binds to. "+
		"Use :8443 for HTTPS or :8080 for HTTP, or leave as 0 to disable the metrics service.")

	var probeAddr string
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "The address the probe endpoint binds to.")

	var enableLeaderElection bool
	flag.BoolVar(&enableLeaderElection, "leader-elect", false,
		"Enable leader election for controller manager. "+
			"Enabling this will ensure there is only one active controller manager.")

	opts := zap.Options{
		DestWriter:  os.Stdout,
		TimeEncoder: zapcore.ISO8601TimeEncoder,
	}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	// INFO: Logger setup.
	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	// INFO: Manager setup.
	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme: scheme,

		// INFO: Metrics endpoint is enabled in 'config/default/kustomization.yaml'. The Metrics options configure the server.
		// More info:
		// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.19.0/pkg/metrics/server
		// - https://book.kubebuilder.io/reference/metrics.html
		Metrics: metricsserver.Options{
			BindAddress:   metricsAddr,
			SecureServing: false,
		},

		WebhookServer: webhook.NewServer(webhook.Options{TLSOpts: []func(*tls.Config){
			func(c *tls.Config) {
				setupLog.Info("disabling http/2")
				c.NextProtos = []string{"http/1.1"}
			},
		}}),

		HealthProbeBindAddress: probeAddr,
		Logger:                 ctrl.Log.WithName("manager"),
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "370a315d.atro.xyz",

		// WARN: If you are using this option, ensure that the program ends immediately after the manager stops.
		// Otherwise, it is unsafe to use this option.
		LeaderElectionReleaseOnCancel: true,
	})
	if err != nil {
		setupLog.Error(err, "unable to start manager")
		os.Exit(1)
	}

	// INFO: Controllers setup.
	if err = (&controller.AppBaseReconciler{
		Client: mgr.GetClient(),
		Scheme: mgr.GetScheme(),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "AppBase")
		os.Exit(2)
	}
	if err = (&controller.AppReconciler{
		Client: mgr.GetClient(),
		Scheme: mgr.GetScheme(),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "App")
		os.Exit(3)
	}
	if os.Getenv("ENABLE_WEBHOOKS") != "false" {
		if err = (&atroxyzv1alpha1.App{}).SetupWebhookWithManager(mgr); err != nil {
			setupLog.Error(err, "unable to create webhook", "webhook", "App")
			os.Exit(4)
		}
	}
	if os.Getenv("ENABLE_WEBHOOKS") != "false" {
		if err = (&atroxyzv1alpha1.AppBase{}).SetupWebhookWithManager(mgr); err != nil {
			setupLog.Error(err, "unable to create webhook", "webhook", "AppBase")
			os.Exit(1)
		}
	}
	// +kubebuilder:scaffold:builder

	// INFO: Health checks.
	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "unable to set up health check")
		os.Exit(5)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "unable to set up ready check")
		os.Exit(6)
	}

	// INFO: Start the manager. By now the manager is fully configured and set up with the controllers.
	setupLog.Info("starting manager")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "problem running manager")
		os.Exit(7)
	}
}
