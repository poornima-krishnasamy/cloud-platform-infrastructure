# Cloud Platform Prometheus

This repository will allow you to create a monitoring namespace in a MoJ Cloud Platform cluster. It will also contain the neseccary values to perform an installation of Prometheus-Operator and Kube-Prometheus. 

  - [Pre-reqs](#pre-reqs)
  - [Creating a monitoring namespace](#creating-a-monitoring-namespace)
  - [Installing Prometheus-Operator](#installing-prometheus-operator)
  - [Installing Kube-Prometheus](#installing-kube-prometheus)
  - [Installing Alertmanager](#installing-alertmanager)
  - [Installing Exporter-Kubelets](#installing-exporter-kubelets)
  - [Exposing the port](#exposing-the-port)
  - [How to tear it all down](#how-to-tear-it-all-down)

```bash
TL;DR
# Copy ./monitoring dir to the namespace dir in the cloud-platform-environments repository.

# Add CoreOS Helm repo
$ helm repo add coreos https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/

# Install prometheus-operator
$ helm install coreos/prometheus-operator --name prometheus-operator --namespace monitoring -f ./helm/prometheus-operator/values.yaml

# Install kube-prometheus
$ helm install coreos/kube-prometheus --name kube-prometheus --set global.rbacEnable=true --namespace monitoring -f ./helm/kube-prometheus/values.yaml

# Expose the Prometheus port to your localhost
$ kubectl port-forward -n monitoring prometheus-kube-prometheus-0 9090

# Expose the AlertManager port to your localhost
$ kubectl port-forward -n monitoring alertmanager-kube-prometheus-0 9093
```

## Pre-reqs
It is assumed that you have authenticated to an MoJ Cloud-Platform Cluster and you have Helm installed and configured.

## Creating a monitoring namespace
To create a monitoring namespace you will need to copy the `./monitoring` directory in this repository to a branch in the [Cloud-Plarform-Environments](https://github.com/ministryofjustice/cloud-platform-environments/tree/master/namespaces). Once this branch has been reviewed and merged to `master` a pipeline is kicked off, creating a namespace called `monitoring`. 

## Installing Prometheus-Operator
> The mission of the Prometheus Operator is to make running Prometheus
> on top of Kubernetes as easy as possible, while preserving
> configurability as well as making the configuration Kubernetes native.
> [https://coreos.com/operators/prometheus/docs/latest/user-guides/getting-started.html](https://coreos.com/operators/prometheus/docs/latest/user-guides/getting-started.html)

The Prometheus Operator provides easy monitoring for Kubernetes services and deployments besides managing Prometheus, Alertmanager and Grafana configuration.

To install Prometheus Operator, run:
```bash
$ helm repo add coreos https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/

$ helm install coreos/prometheus-operator --name prometheus-operator --namespace monitoring -f ./monitoring/helm/prometheus-operator/values.yaml
```
And then confirm the operator is running in the monitoring namspace:
```bash
$ kubectl get pods -n monitoring
```

## Installing Kube-Prometheus
Prometheus is an open source toolkit to monitor and alert, inspired by Google Borg Monitor. It was previously developed by SoundCloud and afterwards donated to the CNCF.

To install kube-prometheus, run:
```bash 
$ helm install coreos/kube-prometheus --name kube-prometheus --set global.rbacEnable=true --namespace monitoring -f ./monitoring/helm/kube-prometheus/values.yaml
```

## Installing AlertManager
> The Alertmanager handles alerts sent by client applications such as the Prometheus server. It takes care of deduplicating, grouping, and routing   them to the correct receiver integration such as email or PagerDuty. It also takes care of silencing and inhibition of alerts - 
> [https://prometheus.io/docs/alerting/alertmanager/](https://prometheus.io/docs/alerting/alertmanager/)

AlertManager can be installed (using a sub-chart) as part of the installtion of Kube-Prometheus.

Set the following entry on the Kube-Prometheus `values.yaml` to true
```yaml
# AlertManager
deployAlertManager: true
```
### Configuring AlertManager to send alerts to PagerDuty

Make note of the `service_key:` key on the Kube-Prometheus `values.yaml` file. 

```yaml
# Add PagerDuty key to allow integration with a PD service. 
    - name: 'pager-duty-high-priority'
      pagerduty_configs:
      - service_key: "$KEY"
```
The `$KEY` value needs to be generated and copied from PagerDuty.

### PagerDuty Service Key retrieval

This is a quick guide on how to retrive your service key from PagerDuty by following these steps:

1) Login to PaderDuty

2) Go to the **Configuration** menu and select **Services**.

3) On the Services page: 

    * If you are creating a new service for your integration, click **Add New Service**.

    * If you are adding your integration to an existing service, click the name of the service you want to add the integration to. Then click the **Integrations** tab and click the **New Integration** button.
4) Select your app from the **Integration Type** menu and enter an **Integration Name**.

5) Click the **Add Service** or **Add Integration** button to save your new integration. You will be redirected to the Integrations page for your service.

6) Copy the **Integration Key** for your new integration.

7) Paste the **Integration Key** into the `service_key` placeholder, `$key` in the configuration `values.yaml` file.

### Slack Intergration Placeholder

PLACEHOLD

## Installing Exporter-Kubelets
Exporter-Kubelets is a simple service that enables container metrics to be scraped by prometheus (also known as cAdvisor)

Exporter-Kubelets can be installed [as a service monitor](https://github.com/coreos/prometheus-operator#customresourcedefinitions) as part of the installation of Kube-Prometheus.

Add the exporter-kubelets value under the serviceMonitorsSelector section:

```yaml
serviceMonitorsSelector:
    matchExpressions:
    - key: app
      operator: In
      values:
      - exporter-kubelets
```

## Exposing the port
Due to a lack of auth options, we've decided to use port forwarding to prevent unauthorised access. Forward the Prometheus server to your machine so you can take a better look at the dashboard by opening http://localhost:9090.
```bash
$ kubectl port-forward -n monitoring prometheus-kube-prometheus-0 9090
```
To Expose the port for AlertManager, run:
```bash
$ kubectl port-forward -n monitoring alertmanager-kube-prometheus-0 9093
```

## How to tear it all down
If you need to uninstall kube-prometheus and the prometheus-operator then you will simple need to run the following:
```bash
$ helm del --purge kube-prometheus && helm del --purge prometheus-operator
```




