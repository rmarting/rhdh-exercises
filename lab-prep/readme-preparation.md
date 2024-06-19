# Lab Preparation

## Start Red Hat OpenShift Container Platform

Request a ["Red Hat OpenShift Container Platform Cluster"](https://demo.redhat.com/catalog?search=openshift&item=babylon-catalog-prod%2Fopenshift-cnv.ocpmulti-wksp-cnv.prod)
instance from [Red Hat Demo Platform](https://demo.redhat.com/).

**NOTE**: You must `cluster-admin` privileges to install the different operators required for this technical exercise.

The content of this repo was tested in Red Hat Developer Hub 1.1 on Red Hat OpenShift Container Platform 4.12.12, 4.14.20, and 4.15.16.

## Install cert-manager operator

Run:

```sh
oc apply -f ./cert-manager-operator.yaml
```

Once the operator is ready you can continue. This command shows the status of this operator:

```sh
on 🎩 ❯ oc get csv -n cert-manager-operator
NAME                            DISPLAY                                       VERSION   REPLACES                        PHASE
cert-manager-operator.v1.13.0   cert-manager Operator for Red Hat OpenShift   1.13.1    cert-manager-operator.v1.13.0   Succeeded
```

## Install GitLab operator

Run:

```sh
oc create namespace gitlab-system
oc apply -f https://gitlab.com/api/v4/projects/18899486/packages/generic/gitlab-operator/0.30.1/gitlab-operator-openshift-0.30.1.yaml
```

## Deploy GitLab

Run:

```sh
export basedomain=$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}')
envsubst < ./gitlab.yaml | oc apply -f -
```

Deploying GitLab takes some time, so check its status as `Running` before continuing with next steps:

```sh
oc get gitlabs gitlab -o jsonpath='{.status.phase}' -n gitlab-system
```

GitLab is now accessible with user `root/<password in "gitlab-gitlab-initial-root-password" secret>`. To get the plain
value of that password:

```sh
oc get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' -n gitlab-system | base64 -d
```

Setup GitLab with some initial configuration:

```sh
./configure-gitlab.sh
```

**NOTE**: If GitLab is deployed using self-signed certificates, you can get the following exception:

`SSL certificate problem: self-signed certificate in certificate chain`

In that case, execute the script with the `--ssl_certs_self_signed=y` argument.

This script will do the following:

```
Create two groups:

- team-a
- team-b

Create two users/passwords:

- user1/@abc1cde2
- user2/@abc1cde2

Ensure `user1` belongs to `team-a` and `user2` belongs to `team-b`.

Create a repo called `sample-app` under `team-a` add the `catalog-info.yaml` and `users-groups.yaml` at the root of the repo.
```

## Install Red Hat Developer Hub operator

Run:

```sh
oc apply -f ./rhdh-operator.yaml
```

The operator is installed in the `rhdh-operator` namespace:

```sh
on 🎩 ❯ oc get csv -n rhdh-operator
NAME                                  DISPLAY                          VERSION                REPLACES               PHASE
rhdh-operator.v1.1.2-0.1714688890.p   Red Hat Developer Hub Operator   1.1.2+0.1714688890.p   rhdh-operator.v1.1.1   Succeeded
```

## Install Red Hat Developer Hub instance

Run:

```sh
oc apply -f ./rhdh-instance.yaml
```

Once the deployment is finished, the status is identified as `Deployed`. This command shows that status:

```sh
oc get backstage developer-hub -o jsonpath='{.status.conditions[0].type}' -n rhdh-gitlab
```

The instance is deployed in the `rhdh-gitlab` namespace and available at:

```sh
echo https://$(oc get route backstage-developer-hub -n rhdh-gitlab -o jsonpath='{.spec.host}')
```

Verify that Red Hat Developer Hub is running.
