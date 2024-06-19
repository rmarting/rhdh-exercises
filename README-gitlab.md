# Red Hat Developer Hub Workshop integrated with GitLab

## Mandatory settings

When Red Hat Developer Hub is installed via the operator there are some mandatory settings that need to be set:

- create mandatory backend secret
- add the `basedomain` to enable proper navigation and cors settings

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-secrets.yaml -n rhdh-gitlab
export basedomain=$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}' | base64 -w0)
oc patch secret rhdh-secrets -n rhdh-gitlab -p '{"data":{"basedomain":"'"${basedomain}"'"}}'
```

Enable custom and external application configuration adding this ConfigMap and Secret to the `developer-hub` manifest:

```yaml
spec:
  application:
    appConfig:
      configMaps:
      - name: app-config-rhdh
    extraEnvs:
      secrets:
        - name: rhdh-secrets
```

or run this:

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-app-configmap-0.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/rhdh-instance-0.yaml -n rhdh-gitlab
```

## Enable GitLab authentication

Create a [new application](https://backstage.io/docs/auth/gitlab/provider):

- name: `rhdh-exercises`
- the call back uri should look something like: `https://backstage-developer-hub-rhdh-gitlab.${OCP_CLUSTER_DOMAIN}/api/auth/gitlab/handler/frame`
- set the correct permissions: `read_user`, `read_repository`, `write_repository`, `openid`, `profile`, `email`

The applications are managed in the profile the user in the menu `Applications`.

Create a secret with an app id and secret:

```yaml
kind: Secret
apiVersion: v1
metadata:
  name: gitlab-secrets
  namespace: rhdh-gitlab
stringData:
  AUTH_GITLAB_CLIENT_ID: REPLACE_WITH_YOUR_GITLAB_CLIENT_ID
  AUTH_GITLAB_CLIENT_SECRET: REPLACE_WITH_YOUR_GITLAB_CLIENT_SECRET
type: Opaque
```

You can create the `gitlab-secrets.yaml` inside of `custom-app-config-gitlab` folder and run:

```sh
oc apply -f ./custom-app-config-gitlab/gitlab-secrets.yaml -n rhdh-gitlab
```

Modify `app-config` with environment variables from the new secret:

```yaml
    app:
      title: Red Hat Developer Hub
    signInPage: gitlab
    auth:
      environment: development
      providers:
        gitlab:
          development:
            clientId: ${AUTH_GITLAB_CLIENT_ID}
            clientSecret: ${AUTH_GITLAB_CLIENT_SECRET}
```

Notice that we set the `signInPage` to `gitlab`, the default is `github`.

To disable guest login set the `environment` to `production` add the new secret to the backstage manifests:

```yaml
spec:
  application:
    ...
    extraEnvs:
      secrets:
        - name: gitlab-secrets
```

Or execute:

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-app-configmap-1.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/rhdh-instance-1.yaml -n rhdh-gitlab
```

Verify that you can login with GitLab.

## Enable GitLab plugin integration

Create new Personal Access Token (aka PAT) in menu `Access Tokens` of the GitLab user profile :

- name: `pat-rhdh-exercises`
- expiration date: Disabled it or just one in the future
- set the scopes: `api`, `read_repository`, `write_repository`

Add the PAT to the previously created `gitlab-secrets` secret:

```yaml
kind: Secret
apiVersion: v1
metadata:
  name: gitlab-secrets
  namespace: rhdh-gitlab
stringData:
  AUTH_GITLAB_CLIENT_ID: REPLACE_WITH_YOUR_GITLAB_CLIENT_ID
  AUTH_GITLAB_CLIENT_SECRET: REPLACE_WITH_YOUR_GITLAB_CLIENT_SECRET
  GITLAB_TOKEN: REPLACE_WITH_YOUR_PAT
type: Opaque
```

And apply changes:

```sh
oc apply -f ./custom-app-config-gitlab/gitlab-secrets.yaml -n rhdh-gitlab
```

Add the following to the `app-config-rhdh` ConfigMap:

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: app-config-rhdh
data:
  app-config-rhdh.yaml: |
    app:
      title: Red Hat Developer Hub
    integrations:
      gitlab:
        - host: gitlab.${basedomain}
          token: ${GITLAB_TOKEN}
          apiBaseUrl: https://gitlab.${basedomain}/api/v4
          baseUrl: https://gitlab.${basedomain}
```

Or execute:

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-app-configmap-2.yaml -n rhdh-gitlab
```

## Add GitLab autodiscovery

Create a new ConfigMap with the needed dynamic plugin:

```sh
oc apply -f ./custom-app-config-gitlab/dynamic-plugins-3.yaml -n rhdh-gitlab
```

Add this to the app config ConfigMap:

```yaml
catalog:
  providers:
    gitlab:
      yourProviderId:
        host: gitlab.${basedomain} # Identifies one of the hosts set up in the integrations
        apiBaseUrl: https://gitlab.${basedomain}/api/v4
        branch: main # Optional. Used to discover on a specific branch
        fallbackBranch: main # Optional. Fallback to be used if there is no default branch configured at the Gitlab repository. It is only used, if `branch` is undefined. Uses `master` as default
        skipForkedRepos: false # Optional. If the project is a fork, skip repository
        entityFilename: catalog-info.yaml # Optional. Defaults to `catalog-info.yaml`
        projectPattern: '[\s\S]*' # Optional. Filters found projects based on provided patter. Defaults to `[\s\S]*`, which means to not filter anything
        schedule: # optional; same options as in TaskScheduleDefinition
          # supports cron, ISO duration, "human duration" as used in code
          frequency: { minutes: 1 }
          # supports ISO duration, "human duration" as used in code
          timeout: { minutes: 3 }
```

Or execute:

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-app-configmap-3.yaml -n rhdh-gitlab
```

Update the backstage manifest to use the new ConfigMap for plugins:

```yaml
spec:
  application:
  ...
    dynamicPluginsConfigMapName: dynamic-plugins-rhdh
```

Or run:

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-instance-3.yaml -n rhdh-gitlab
```

Verify that the `sample-service` component is in the application catalog.

## Enable users/teams autodiscovery

Add this to the ConfigMap:

```yaml
  catalog:
    providers:
      gitlab:
        yourProviderId:
          host: gitlab.${basedomain}
            orgEnabled: true
            #group: org/teams # Required for gitlab.com when `orgEnabled: true`. Optional for self managed. Must not end with slash. Accepts only groups under the provided path (which will be stripped)
            allowInherited: true # Allow groups to be ingested even if there are no direct members.
            groupPattern: '[\s\S]*'
```

Or run:

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-app-configmap-4.yaml -n rhdh-gitlab
```

**ATTENTION**: This step is broken due to this [issue](https://issues.redhat.com/browse/RHIDP-1713).
We will emulate what the processor would have done by registering the [`users-groups.yaml`](./lab-prep/users-groups.yaml)
to Red Hat Developer Hub:

![Register an Existing Component!](./media/Register-an-existing-component.png "Register-an-existing-component")

Verify that users and teams are discovered.

## Enable RBAC

Enable permissions by updating `app-config-rhdh` ConfigMap:

```yaml
permission:
  enabled: true
  rbac:
    admin:
      users:
        - name: user:default/1
    policies-csv-file: /permissions/rbac-policy.csv
```

Mount the new file in the `Backstage` manifests:

```yaml
    extraFiles:
      mountPath: /opt/app-root/src
      configMaps:
        - name: rbac-policy
          key: rbac-policy.csv
```

Create a new permission file, see [`permission-configmap-5.yaml`](./custom-app-config-gitlab/permission-configmap-5.yaml) file.

There is a dynamic plugin to allow manage the RBAC rules directly in the UI. This plugin is added in the list of the dynamic plugins
to add into Red Hat Developer Hub.

```sh
oc apply -f ./custom-app-config-gitlab/dynamic-plugins-5.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/permission-configmap-5.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/rhdh-app-configmap-5.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/rhdh-instance-5.yaml -n rhdh-gitlab
```

Verify that `user2` cannot see `sample-service` anymore.

References:

* [RBAC in Red Hat Developer Hub](https://access.redhat.com/documentation/en-us/red_hat_developer_hub/1.1/html/administration_guide_for_red_hat_developer_hub/con-rbac-overview_admin-rhdh#doc-wrapper)

## Import Software Template

Software templates are the way to create standard components integrated with the platform, and any tool
related to that component. This [template](https://github.com/rmarting/rhdh-exercises-software-templates/blob/main/templates.yaml)
is a simple case of this kind of component.

Templates can be registered from the `Create...` menu. The `Register Existing Component` button opens a wizard to register the component
from the remote url.

Another alternative is to configure the location of the templates in the `catalog` definition. This is the
configuration to add in the `app-config-rhdh` ConfigMap:

```yaml
    catalog:
      locations:
        - type: url
          target: https://github.com/rmarting/rhdh-exercises-software-templates/blob/main/templates.yaml
          rules:
            - allow: [Template]
```

Or run:

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-app-configmap-6.yaml -n rhdh-gitlab
```

It is needed to restart the Red Hat Developer Hub deployment to load the new configuration from the ConfigMap. One
way to restart can be:

```sh
oc scale --replicas=0 deployment/backstage-developer-hub -n rhdh-gitlab
oc scale --replicas=1 deployment/backstage-developer-hub -n rhdh-gitlab
```

Verify the new Software Templates clicking in the `Create...` button.

## Create a component

Create a new component from a Software Template is a simple process. Create a new component
from the `Sample Software Template from Backstage` template.

Fulfil the parameters requested:

- Name - an unique name of this new component
- Description (Optional)
- Owner - Choose one from the list of options, or add one such as `team-a`, or `team-b` (Remove the `group:` or `user:` prefix)
- Repository Location - Location of the GitLab server instance.

To get the repository location run:

```sh
echo gitlab.$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}')
```

Verify that your new component is listed in the Catalog.

## Deploy a dynamic plugin

Another capability of Red Hat Developer Hub is add dynamic plugins easily. This exercise will deploy a dynamic
plugin defined in this [repo](https://github.com/rmarting/rhdh-dynamic-devquote-plugin)

Previously we added the definition of the GitLab catalog backend plugin, now we will extend the list of dynamic
plugins including the new one with the following configuration:

```yaml
    plugins:
      - package: './dynamic-plugins/dist/backstage-plugin-catalog-backend-module-gitlab-dynamic'
        disabled: false
        pluginConfig: {}
      - package: './dynamic-plugins/dist/janus-idp-backstage-plugin-rbac'
        disabled: false
        pluginConfig: {}
      - package: '@rmarting/my-devquote-plugin@0.0.2'
        integrity: sha512-S/CbM8s8vqVMeBeWGJ/4SsCd2b6K8Ngp992H1JN6HdwB9QiupPZu5wfnEpjN024SJemd/VUFT53tiUGrt1J/dw==
        disabled: false
        pluginConfig:
          dynamicPlugins:
            frontend:
              rmarting.my-devquote-plugin:
                mountPoints:
                  - config:
                      layout:
                        gridColumnEnd:
                          lg: span 4
                          md: span 6
                          xs: span 12
                    importName: DevQuote
                    mountPoint: entity.page.overview/cards
                dynamicRoutes:
                  - importName: DevQuote
                    menuItem:
                      text: Quote
                    path: /devquote
```

Or run:

```sh
oc apply -f ./custom-app-config-gitlab/dynamic-plugins-7.yaml -n rhdh-gitlab
```

It is needed to restart the Red Hat Developer Hub deployment to load the new configuration from the ConfigMap. One
way to restart can be:

```sh
oc scale --replicas=0 deployment/backstage-developer-hub -n rhdh-gitlab
oc scale --replicas=1 deployment/backstage-developer-hub -n rhdh-gitlab
```

Verify the `Quote` menu is listed, and a quote is showed in any component dashboard.

## Enable Tech Docs

### Create Storage

Create a new Storage component by OpenShift Data Foundation in the same namespace
where Red Hat Developer Hub is running:

```sh
oc apply -f ./custom-app-config-gitlab/obc-8.yaml -n rhdh-gitlab
```

Once the object is created, a new ConfigMap and Secret are created both with the
name of the `ObjectBucketClaim` resource. In our case, `rhdh-exercises-bucket-claim`.
These resources include a set of properties to identify the new bucket in AWS.

* `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` as credentials of this new bucket
* `BUCKET_HOST`, `BUCKET_NAME`, ... to identify the new bucket

Some of these values are needed in the following steps:

### Deploy GitLab runner

The technical docs will be created as part of the CI pipelines of the components, so
we need to set up the GitLab instance to run pipelines and use some variables to
identify the new bucket to store the results.

Deploy a GitLab runner to run pipelines:

```sh
export basedomain=$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}')
envsubst < ./custom-app-config-gitlab/gitlab-runner-8.yaml | oc apply -n gitlab-system -f -
```

GitLab requires a set of CI variables to run successfully the techdocs pipelines.
Login as `root` into GitLab and add these variables in `Admin Area / CI/CD / Variables`:

* `AWS_ENDPOINT`: Output of the command `oc get route s3 -n openshift-storage -o jsonpath='https://{.spec.host}'`
* `AWS_ACCESS_KEY_ID`
* `AWS_SECRET_ACCESS_KEY`
* `TECHDOCS_S3_BUCKET_NAME`: Value of `BUCKET_NAME` variable
* `AWS_REGION`: `us-east-2`

The configuration should be similar to:

![GitLab CICD Variables](./media/gitlab-admin-cicd-variables.png)

### Set up techdocs plugin

Patch the `rhdh-secrets` secret to add the `AWS_REGION` and `BUCKET_URL` variables:

```sh
export AWS_REGION=$(echo -n 'us-east-2' | base64 -w0)
export BUCKET_URL=$(oc get route s3 -n openshift-storage -o jsonpath='https://{.spec.host}' | base64 -w0)
oc patch secret rhdh-secrets -n rhdh-gitlab -p '{"data":{"AWS_REGION":"'"${AWS_REGION}"'"}}'
oc patch secret rhdh-secrets -n rhdh-gitlab -p '{"data":{"BUCKET_URL":"'"${BUCKET_URL}"'"}}'
```

Add the `rhdh-exercises-bucket-claim` ConfigMap and Secret to the Red Hat Developer Hub deployment.

```yaml
    extraEnvs:
      envs:
        # Disabling TLS verification
        - name: NODE_TLS_REJECT_UNAUTHORIZED
          value: '0'
      configMaps:
        - name: rhdh-exercises-bucket-claim
      secrets:
        - name: gitlab-secrets
        - name: rhdh-secrets
        - name: rhdh-exercises-bucket-claim
```

And apply changes to the application configuration:

```yaml
    techdocs:
      builder: 'external'
      generator:
        runIn: 'local'
      publisher:
        type: 'awsS3'
        awsS3:
          bucketName: ${BUCKET_NAME}
          endpoint: ${BUCKET_URL}
          s3ForcePathStyle: true
          region: ${AWS_REGION}
          credentials:
            accessKeyId: ${AWS_ACCESS_KEY_ID}
            secretAccessKey: ${AWS_SECRET_ACCESS_KEY}
```

Or run:

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-app-configmap-8.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/rhdh-instance-8.yaml -n rhdh-gitlab
```

Modify the content of the `docs/index.md` file of your component, check the CI pipeline
is executed successfully and verify the technical content in Red Hat Developer Hub.

**ATTENTION**: This step is broken due to this [issue](https://issues.redhat.com/browse/RHIDP-2204).
It is fixed in Red Hat Developer Hub 1.2. Meanwhile, if you want to test it, RBAC must be disabled:

```yaml
    permission:
      enabled: false
```

Restart the pod, and your technical documentation is available.
