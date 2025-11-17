# Lab Preparation

## Start Red Hat OpenShift Container Platform

This repository was tested and verified in the following environments provided by the [Red Hat Demo Platform](https://demo.redhat.com/):

* [Red Hat OpenShift Container Platform Cluster](https://demo.redhat.com/catalog?item=babylon-catalog-prod/sandboxes-gpte.ocp-wksp.prod)
* [OpenShift Single Node Cluster](https://demo.redhat.com/catalog?item=babylon-catalog-prod%2Fopenshift-cnv.ocpmulti-single-node-cnv.prod)

In both cases, request at least 64GB RAM memory.

**NOTE**: You must `cluster-admin` privileges to install the different operators required for this technical exercise.

The content of this repo was tested in Red Hat Developer Hub 1.8.0 on Red Hat OpenShift Container Platform 4.18.

## Install cert-manager operator

Check if the Cert Manager operator is already available in your cluster:

```shell
on 🎩 ❯ oc get csv -n cert-manager-operator
NAME                            DISPLAY                                       VERSION   REPLACES                        PHASE
cert-manager-operator.v1.18.0   cert-manager Operator for Red Hat OpenShift   1.18.0    cert-manager-operator.v1.17.0   Succeeded
```

If you don't get a response similar to the previous output, then execute this command:

```shell
oc apply -f ./lab-prep/cert-manager-operator.yaml
```

Once the operator is ready you can continue. This command shows the status of this operator:

```shell
on 🎩 ❯ oc get csv -n cert-manager-operator
NAME                            DISPLAY                                       VERSION   REPLACES                        PHASE
cert-manager-operator.v1.18.0   cert-manager Operator for Red Hat OpenShift   1.18.0    cert-manager-operator.v1.17.0   Succeeded
```

**NOTE:** Please, wait until the operator is installed successfully before continue with the preparations. Otherwise, you can face other issues.

## Install GitLab operator

Run:

```shell
oc apply -f ./lab-prep/gitlab-operator.yaml
```

The operator is installed in the `gitlab-system` namespace. Check the status of the operator by:

```shell
on 🎩 ❯ oc get csv -n gitlab-system
NAME                                DISPLAY    VERSION   REPLACES                            PHASE
gitlab-operator-kubernetes.v2.5.2   GitLab     2.5.2     gitlab-operator-kubernetes.v2.5.0   Succeeded
```

## Deploy GitLab

Run:

```shell
export basedomain=$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}')
envsubst < ./lab-prep/gitlab.yaml | oc apply -f -
```

Deploying GitLab takes some time, so check its status as `Running` before continuing with next steps:

```shell
oc get gitlabs gitlab -o jsonpath='{.status.phase}' -n gitlab-system
```

GitLab is now accessible with user `root/<password in "gitlab-gitlab-initial-root-password" secret>`. To get the plain
value of that password:

```shell
oc get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' -n gitlab-system | base64 -d
```

Setup GitLab with some initial configuration:

```shell
./lab-prep/configure-gitlab.sh
```

The initial configuration requires to push some content into GitLab, you should use the `user1` credentials to do it.

**WARNING**: If GitLab is deployed using self-signed certificates, you can get the following exception:

`SSL certificate problem: self-signed certificate in certificate chain`

In that case, execute the script with the `--ssl_certs_self_signed=y` argument.

This script will do the following:

```
Create different groups:

- team-a
- team-b
- rhdh

Create two users/passwords:

- user1/@abc1cde2
- user2/@abc1cde2

Ensure `user1` belongs to `team-a` and `user2` belongs to `team-b`.

Create a repo called `sample-app` under `team-a` add the `catalog-info.yaml` and `users-groups.yaml` at the root of the repo.
```

## Install Red Hat Developer Hub operator

Run:

```shell
oc apply -f ./lab-prep/rhdh-operator.yaml
```

The operator is installed in the `rhdh-operator` namespace:

```shell
on 🎩 ❯ oc get csv -n rhdh-operator
NAME                   DISPLAY                          VERSION   REPLACES               PHASE
rhdh-operator.v1.8.0   Red Hat Developer Hub Operator   1.8.0     rhdh-operator.v1.7.1   Succeeded
```

## Install Red Hat Developer Hub instance

Run:

```shell
oc apply -f ./lab-prep/rhdh-instance.yaml
```

Once the deployment is finished, the status is identified as `Deployed`. This command shows that status:

```shell
oc get backstage developer-hub -o jsonpath='{.status.conditions[0].type}' -n rhdh-gitlab
```

The instance is deployed in the `rhdh-gitlab` namespace and available at:

```shell
echo https://$(oc get route backstage-developer-hub -n rhdh-gitlab -o jsonpath='{.spec.host}')
```

Verify that Red Hat Developer Hub is running.
