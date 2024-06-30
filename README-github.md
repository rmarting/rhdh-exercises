# rhdh-exercises

## Installation

```sh
oc apply -f rhdh-installation/operator.yaml
oc apply -f rhdh-installation/rhdh-instance.yaml
```

## Start customizing

```sh
oc apply -f ./custom-app-config/rhdh-app-configmap.yaml -n rhdh
oc apply -f ./custom-app-config/rhdh-instance.yaml -n rhdh
```

apply the needed mandaroy backend auth key secret

```sh
oc apply -f ./custom-app-config/rhdh-secrets.yaml -n rhdh
export basedomain=$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}' | base64 -w0)
oc patch secret rhdh-secrets -n rhdh -p '{"data":{"basedomain":"'"${basedomain}"'"}}'
```

add this configmap to the rhdh manifest:

```yaml
spec:
  application:
    appConfig:
      configMaps:
      - name: app-config-rhdh
```

## Enable github authentication

create a new organization
create a new oauth application
create a secret with a client id and secret

```yaml
kind: Secret
apiVersion: v1
metadata:
  name: github-secrets
  namespace: rhdh
data:
  GITHUB_APP_CLIENT_ID: xxx
  GITHUB_APP_CLIENT_SECRET: xxx
type: Opaque
```
modify app config with the new secret

```yaml
    app:
      title: My Red Hat Developer Hub Instance
    auth:
      # see https://backstage.io/docs/auth/ to learn about auth providers
      environment: development
      providers:
        github:
          development:
            clientId: ${GITHUB_APP_CLIENT_ID}
            clientSecret: ${GITHUB_APP_CLIENT_SECRET}
```

or execute

```sh
oc apply -f ./custom-app-config/rhdh-app-configmap-1.yaml -n rhdh
oc apply -f ./custom-app-config/rhdh-instance-1.yaml -n rhdh
```

add the new secret to the backstage manifests

```yaml
spec:
  application:
    ...
    extraEnvs:
      secrets:
        - name: github-secrets
```

## Enable github plugin integration

create new github application
install the application in the organization
add the following to the previously created github-secrets secret

```yaml
kind: Secret
apiVersion: v1
metadata:
  name: github-secrets
  namespace: rhdh
data:
  GITHUB_APP_CLIENT_ID: xxx
  GITHUB_APP_CLIENT_SECRET: xxx
  GITHUB_APP_APP_ID: xxx
  GITHUB_APP_WEBHOOK_URL: none
  GITHUB_APP_WEBHOOK_SECRET: none
  GITHUB_APP_PRIVATE_KEY: xxx
type: Opaque
```

add the following to the appconfig configmap

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: app-config-rhdh
data:
  app-config-rhdh.yaml: |
    app:
      title: My Red Hat Developer Hub Instance
    integrations:
      github:
        - host: github.com
          apps:
            - appId: ${GITHUB_APP_APP_ID}
              clientId: ${GITHUB_APP_CLIENT_ID}
              clientSecret: ${GITHUB_APP_CLIENT_SECRET}
              webhookUrl: ${GITHUB_APP_WEBHOOK_URL}
              webhookSecret: ${GITHUB_APP_WEBHOOK_SECRET}
              privateKey: |
                ${GITHUB_APP_PRIVATE_KEY}
```

or execute

```sh
oc apply -f ./custom-app-config/rhdh-app-configmap-2.yaml -n rhdh
```


## add github autodiscovery

create a new configmap with the plugins

```sh
oc apply -f ./custom-app-config/dynamic-plugins-3.yaml -n rhdh
```

add this to the configmap:

```yaml
      catalog:
        providers:
          github:
            providerId:
              organization: '${GITHUB_ORG}'
            schedule:
              frequency:
                minutes: 30
              initialDelay:
                seconds: 15
              timeout:
                minutes: 3
```

```sh
oc apply -f ./custom-app-config/rhdh-app-configmap-3.yaml -n rhdh
```

update  the backstage manifest to use the new configmap for plugins

```yaml
spec:
  application:
  ...
    dynamicPluginsConfigMapName: dynamic-plugins-rhdh
```

```sh
oc apply -f ./custom-app-config/rhdh-instance-3.yaml -n rhdh
```

## enable users/teams autodiscovery

update the dynamic plugin configmap

```sh
oc apply -f ./custom-app-config/dynamic-plugins-4.yaml -n rhdh
```

add this to the configmap:

```yaml
    catalog:
      providers:
        githubOrg:
          id: production
          githubUrl: "${GITHUB_URL}"
          orgs: [ "${GITHUB_ORG}" ]
```

```sh
oc apply -f ./custom-app-config/rhdh-app-configmap-4.yaml -n rhdh
```