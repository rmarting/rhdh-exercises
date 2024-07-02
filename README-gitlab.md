# Red Hat Developer Hub Workshop integrated with GitLab

## Mandatory settings

When Red Hat Developer Hub is installed via the operator there are some mandatory settings that need to be set:

- create mandatory backend secret
- add the `basedomain` to enable proper navigation and CORs settings

Customizing the instance requires a custom application file defined in a ConfigMap object. Additionally we can use a
Secret object to store sensitive data required by Red Hat Developer Hub. An example of sensitive data required is
the `BACKEND_SECRET` variable. That variable contains a mandatory backend authentication key.

Creating a Secret including that variable, and adding the base domain of our instance can be done running:

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-secrets.yaml -n rhdh-gitlab
oc patch secret rhdh-secrets -n rhdh-gitlab -p '{"stringData":{"basedomain":"'"${basedomain}"'"}}'
```

This is the structure of the `app-config-rhdh` ConfigMap to customize the configuration of our Red Hat Developer Hub instance:

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: app-config-rhdh
data:
  app-config-rhdh.yaml: |
    app:
      title: My Red Hat Developer Hub Instance
      baseUrl: https://backstage-developer-hub-rhdh-gitlab.${basedomain}
    backend:
      auth:
        keys:
          - secret: ${BACKEND_SECRET}
      baseUrl: https://backstage-developer-hub-rhdh-gitlab.${basedomain}
      cors:
        origin: https://backstage-developer-hub-rhdh-gitlab.${basedomain}
```

Once created the ConfigMap and Secret, we can add them into the `developer-hub` CR Red Hat Developer Hub manifest:

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

**ATTENTION**: Red Hat Developer Hub has a slow startup as it is building and loading the dynamic plugins. Every time
we apply a [change in the configuration](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.2/html-single/release_notes_for_red_hat_developer_hub_1.2/index#enhancement-to-configmap-or-secret-configuration),
an automatic redeploy will start, and it will few minutes until
the new pod is ready to serve request. Please, be patient after any change before confirming they are
correctly applied.

More detailed information about this step [here](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.2/html-single/getting_started_with_red_hat_developer_hub/index#proc-add-custom-app-config-file-ocp-operator_rhdh-getting-started.)

## Enable GitLab authentication

Enabling GitLab authentication requires to create a GitLab application within our GitLab instance. This
process is described [here](https://backstage.io/docs/auth/gitlab/provider), however, keep in mind to
execute the actions in your GitLab instance:

- GitLab UI navigation: Edit Profile -> Applications -> Add new application
- name: `rhdh-exercises`
- Redirect URI: copy output `echo https://backstage-developer-hub-rhdh-gitlab.${basedomain}/api/auth/gitlab/handler/frame`
- set the correct permissions: `read_user`, `read_repository`, `write_repository`, `openid`, `profile`, `email`

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

Modify `app-config` section of the `app-config-rhdh` ConfigMap with environment variables from the new secret:

```yaml
    signInPage: gitlab
    auth:
      environment: development
      providers:
        gitlab:
          development:
            clientId: ${AUTH_GITLAB_CLIENT_ID}
            clientSecret: ${AUTH_GITLAB_CLIENT_SECRET}
            audience: https://gitlab.${basedomain}
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

The GitLab integration has a special entity provider for discovering catalog entities from GitLab. The entity provider
will crawl the GitLab instance and register entities matching the configured paths. This can be useful as an alternative
to static locations or manually adding things to the catalog.

More information about Dynamic Plugins [here](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.2/html-single/configuring_plugins_in_red_hat_developer_hub/index#rhdh-installing-dynamic-plugins).

To enable the GitLab integration and discovery capabilities a Personal Access Token (aka PAT) is required.

Create new Personal Access Token (aka PAT) in menu `Access Tokens` of the GitLab user profile:

- GitLab UI navigation: Edit Profile -> Access Tokens -> Add new token
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

Add the following to the `app-config-rhdh` ConfigMap:

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
      gitlab:
        - host: gitlab.${basedomain}
          token: ${GITLAB_TOKEN}
          apiBaseUrl: https://gitlab.${basedomain}/api/v4
          baseUrl: https://gitlab.${basedomain}
```

Or execute:

```sh
oc apply -f ./custom-app-config-gitlab/gitlab-secrets.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/rhdh-app-configmap-2.yaml -n rhdh-gitlab
```

## Add GitLab autodiscovery

Once we have integrated GitLab with Red Hat Developer Hub, we need to enable the autodiscovery
capabilities of this provider. Very useful to load our catalog with repositories already created in
our GitLab server. That requires to enable the `backstage-plugin-catalog-backend-module-gitlab-dynamic`
dynamic plugin provided by Red Hat Developer Hub.

We will use a new ConfigMap to enable the dynamic plugins:

```sh
oc apply -f ./custom-app-config-gitlab/dynamic-plugins-3.yaml -n rhdh-gitlab
```

Add this to the `app-config-rhdh` ConfigMap:

```yaml
catalog:
  providers:
    gitlab:
      myGitLab:
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

Update the Red Hat Developer Hub manifest to use the new ConfigMap for plugins:

```yaml
spec:
  application:
  ...
    dynamicPluginsConfigMapName: dynamic-plugins-rhdh
```

Or run:

```sh
oc apply -f ./custom-app-config-gitlab/rhdh-app-configmap-3.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/rhdh-instance-3.yaml -n rhdh-gitlab
```

Verify that the `sample-service` component is located on the `Catalog` page.

## Enable users/teams autodiscovery

The Red Hat Developer Hub catalog can be set up to ingest organizational data -- users and groups -- directly from GitLab.
The result is a hierarchy of User and Group entities that mirrors your org setup.

Add this to the ConfigMap:

```yaml
  catalog:
    providers:
      gitlab:
        myGitLab:
          host: gitlab.${basedomain}
          orgEnabled: true
          #group: org/teams # Required for gitlab.com when `orgEnabled: true`. Optional for self managed. Must not end with slash. Accepts only groups under the provided path (which will be stripped)
          allowInherited: true # Allow groups to be ingested even if there are no direct members.
          groupPattern: '[\s\S]*'
          restrictUsersToGroup: false
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

Open an incognito window, or just logout, and login with `user2` (password: `@abc1cde2`) to confirm
that the component `sample-service` is not accessible on the `Catalog` page. You can check that
the `user1` can still access to that component successfully.

References:

* [RBAC in Red Hat Developer Hub](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.2/html/administration_guide_for_red_hat_developer_hub/con-rbac-overview_assembly-rhdh-integration-aks)

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

Verify there is a new Software Template available on the `Create...` page.

## Create a component

Creating a new component from a Software Template is a simple process. Create a new component
from the `Sample Software Template from Backstage` template.

Fulfil the parameters requested:

- Name - an unique name of this new component
- Description (Optional)
- Owner - Choose one from the list of options, or add one such as `team-a`, or `team-b` (Remove the `group:` or `user:` prefix)
- Repository Location: Copy output: `echo gitlab.${basedomain}`. Note that `https://` is not included.

To get the repository location run:

```sh
echo gitlab.$(oc get ingresscontroller -n openshift-ingress-operator default -o jsonpath='{.status.domain}')
```

Verify that your new component is listed on the `Catalog` page.

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

Verify the `Quote` menu is listed, and a quote is showed in any component dashboard.

