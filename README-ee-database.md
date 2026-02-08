# Enterprise Labs - Use an External Database

By default, Red Hat Developer Hub uses a database created and managed by the operator, which is
suitable for development or testing. This exercise shows how to recreate a full Red Hat Developer
Hub setup using an **external database** (a PostgreSQL instance created by a StatefulSet) as an
example. Other options (e.g. managed database services) are possible; this lab focuses on the
StatefulSet approach.

## Table of Contents

- [Activity Overview](#activity-overview)
- [Destroy the Current Red Hat Developer Hub](#destroy-the-current-red-hat-developer-hub)
- [Create the External Database](#create-the-external-database)
- [Configure Red Hat Developer Hub to Use the External Database](#configure-red-hat-developer-hub-to-use-the-external-database)
- [Create the SonataFlowPlatform](#create-the-sonataflowplatform)
- [Enable Orchestrator Plugins](#enable-orchestrator-plugins)
- [Verification](#verification)
- [References](#references)

> **Demo-Only Approach: This exercise uses a destroy-then-recreate approach for demonstration purposes only.**
> 
> The steps below **destroy the existing Red Hat Developer Hub instance** and then create everything
> from scratch using an external database. This is **not** the recommended approach for production or
> environments where you need to preserve data.
> 
> In a proper migration you would:
> 
> 1. Export data from the existing (operator-managed) database.
> 2. Create or prepare the external database.
> 3. Import the exported data into the new database.
> 4. Reconfigure Red Hat Developer Hub to use the external database and validate.
> 
> **Data export/import and migration procedures are out of scope for this exercise.** The destroy-and-recreate flow is intended only to illustrate configuration and ordering of resources when using an external database (e.g. StatefulSet-based PostgreSQL).

## Activity Overview

This activity will:

1. **Destroy** the current Red Hat Developer Hub instance and related resources (including
   dynamic plugins PVC and Orchestrator workflows).
2. **Create** an external PostgreSQL database (StatefulSet) in the same namespace.
3. **Recreate** Red Hat Developer Hub from scratch, configured to use that external database
   (with local DB disabled and credentials provided via a secret).
4. **Re-enable** the Orchestrator and install the greeting workflow using the new database
   configuration.

Ensure you have applied all prior exercise configurations (GitLab auth, catalog, RBAC, TechDocs,
etc.) as needed, or re-apply them after recreating the instance.

## Destroy the Current Red Hat Developer Hub

Remove the existing Red Hat Developer Hub instance and associated resources, and
any SonataFlowPlatform resources, and the greeting workflow.

```bash
oc delete backstage developer-hub -n rhdh-gitlab
oc delete pvc dynamic-plugins-root -n rhdh-gitlab
oc delete sonataflowplatform --all -n rhdh-gitlab
helm uninstall greeting-workflow -n rhdh-gitlab
```

Wait until the resources are gone before continuing.

## Create the External Database

Install the PostgreSQL database instance using the provided StatefulSet manifest:

```bash
oc apply -f ./custom-app-config-gitlab/postgresql-my-backstage-psql-statefulset.yaml -n rhdh-gitlab
```

**NOTE**: There are other ways to create an external PostgreSQL database but they are out of the
scope of this exercise.

Wait for the PostgreSQL pod to be ready (e.g. `oc get pods -n rhdh-gitlab -l app=my-backstage-psql-developer-hub`).

If you use Red Hat Developer Lightspeed, create the Lightspeed database in the same PostgreSQL
instance, as in the Lightspeed integration exercise:

```bash
oc exec -n rhdh-gitlab my-backstage-psql-developer-hub-0 -- env PGPASSWORD="$PG_ADMIN_PASS" psql -U postgres -h 127.0.0.1 -p 5432 -c "CREATE DATABASE \"rhdh-ls\";"
```

## Configure Red Hat Developer Hub to Use the External Database

The Backstage custom resource must be updated to:

- Disable the local (operator-managed) database: set `database.enableLocalDb: false`.
- Reference the new secret that contains the credentials and connection details for the
external database.
- Recreate the associated resources removed previously.

```bash
oc apply -f ./custom-app-config-gitlab/dynamic-plugins-root-pvc-10.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/dynamic-plugins-16-no-orchestrator.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/rhdh-instance-16.yaml -n rhdh-gitlab
```

The `rhdh-instance-16.yaml` should contain the database section similar to:

```yaml
  database:
    enableLocalDb: false
```

and the reference to the secret that holds the external database credentials:

```yaml
    extraEnvs:
      configMaps:
        - name: rhdh-techdocs-bucket-claim        
      secrets:
        - name: gitlab-secrets
        - name: rhdh-secrets
        - name: rhdh-techdocs-bucket-claim
        - name: my-backstage-psql-secret-developer-hub
```

Wait for the Red Hat Developer Hub pods to become ready.

## Create the SonataFlowPlatform

The Orchestrator Plugins use the same database created by the operator to persist the workflow
executions and other stuff. We need to recreate those references in the new database before
enabling the plugins:

```bash
oc apply -f ./custom-app-config-gitlab/orchestrator-sonataflowplatform-init-16.yaml -n rhdh-gitlab
```

The manifests used are similar to the ones created by the operator, but using the new database
configuration.

Wait for the SonataFlowPlatform and its pods to be ready.

## Enable Orchestrator Plugins

After the new Red Hat Developer Hub instance is running correctly, enable the Orchestrator plugins
(which use the new database configuration) and remove any dependencies on the previous
SonataFlow setup. Then recreate the SonataFlowPlatform with the final configuration:

```bash
oc apply -f ./custom-app-config-gitlab/dynamic-plugins-16-orchestrator.yaml -n rhdh-gitlab
oc apply -f ./custom-app-config-gitlab/orchestrator-sonataflowplatform-16.yaml -n rhdh-gitlab
```

This creates new SonataFlow instances using the external database. Wait for pods to stabilize.

Install the greeting workflow, configured to use the new database connection (e.g. via the
values in `greeting-values-16.yaml`):

```bash
helm repo add workflows https://redhat-ads-tech.github.io/orchestrator-workflows/
helm repo update workflows
helm upgrade -i greeting-workflow workflows/greeting -f ./custom-app-config-gitlab/greeting-values-16.yaml -n rhdh-gitlab
```

## Verification

Confirm that the configuration matches your expectations and that the new instance has the same
features enabled (auth, catalog, RBAC, TechDocs, etc.), with entities and plugins loaded from
GitLab as in the original setup.

**Data that is not preserved** (because the previous instance was destroyed rather than migrated):

- Workflow executions
- Notifications
- Chat histories (e.g. Lightspeed)

In production, you would perform an export/import of the database to preserve this information;
that procedure is out of scope for this exercise.

## References

- [RHDH Operator - Database migration](https://github.com/redhat-developer/rhdh-operator/blob/main/docs/db_migration.md)
