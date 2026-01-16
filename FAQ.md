# FAQ

Here there is a list of common issues and a workaround to fix them:

## Table of Contents

- [Error - Too many clients](#ansible-plug-ins-for-red-hat-developer-hub)

## ERROR - Too many clients 

It is possible that you PostgreSQL Database reach out its connection
limits with an error similar to:

```log
    Error: Failed to instantiate service 'core.httpRouter' for 'user-settings' because the factory function threw an error, Error: Failed to instantiate service 'core.auth' for 'user-settings' because the factory function threw an error, error: sorry, too many clients already
``` 

The default configuration of the PostgreSQL Database for the `POSTGRESQL_MAX_CONNECTIONS`
env var is 100, which it could be too low for your test.

At this moment the Red Hat Developer Hub Operator does not allow
to inject specific variables, as the most common way to use the
database is using an deploying one outside of the Operator life
cycle. However, there is a workaround to override the default
configuration of the database.

Create a new ConfigMap to declare the configuration of the
StatefulSet used to manage the PostgreSQL Database.
The file [postgresql-configmap.yaml](./custom-app-config-gitlab/postgresql-configmap.yaml) includes an example, where that
variable is override with a higher value.

Second we need to extend the `Backstage` CR to declare the usage
of that ConfigMap to inject directly the configuration to the
StatefulSet. 

The file [rhdh-instance-postgresql-config.yaml](./custom-app-config-gitlab/rhdh-instance-postgresql-config.yaml) includes an example using the `rawRuntimeConfig` for that.

Applying those files will increase the number of connections, and
we could scale up more replicas:

```bash
oc apply -f ./custom-app-config-gitlab/postgresql-configmap.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/rhdh-instance-postgresql-config.yaml -n rhdh-gitlab
```

References:

* [Operator - Raw Configuration](https://github.com/redhat-developer/rhdh-operator/blob/main/docs/configuration.md#raw-configuration)
* [Operator - DB StatefulSet](https://github.com/redhat-developer/rhdh-operator/blob/main/config/profile/rhdh/default-config/db-statefulset.yaml)
