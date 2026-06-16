# Red Hat Developer Hub Workshop

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
![Tag](https://img.shields.io/github/v/tag/rmarting/rhdh-exercises?style=flat-square)
![Last Commit](https://img.shields.io/github/last-commit/rmarting/rhdh-exercises?style=flat-square)
![Technology](https://img.shields.io/badge/tech-Red%20Hat%20Developer%20Hub-red?style=flat-square)
![Language](https://img.shields.io/github/languages/top/rmarting/rhdh-exercises?style=flat-square)
[![Dev Spaces](https://img.shields.io/static/v1?label=open%20in&message=developer%20sandbox&logo=eclipseche&color=FDB940&labelColor=525C86)](https://workspaces.openshift.com/#https://github.com/rmarting/rhdh-exercises.git)

## Table of Contents

1. [Overview](#overview)
2. [Workshop content (Showroom)](#workshop-content-showroom)
3. [FAQ](#faq)
4. [Contributing](#contributing)

---

## Overview

This repository is a hands-on workshop for installing and configuring **Red Hat Developer Hub**
on **Red Hat OpenShift** with some common integrations.

## Workshop content (Showroom)

The workshop content is available on-line as GitHub Pages [here](http://blog.jromanmartin.io/rhdh-exercises/).
Please, use to to run it and learn about Red Hat Developer Hub.

The primary learner path is the Showroom workshop under `content/`:

| File | Purpose |
|------|---------|
| [`site.yml`](./site.yml) | Antora playbook for Showroom publishing |
| [`ui-config.yml`](./ui-config.yml) | Split-view tabs (Terminal, OCP Console, RHDH) |
| [`content/modules/ROOT/pages/index.adoc`](./content/modules/ROOT/pages/index.adoc) | Facilitator index |
| [`content/modules/ROOT/nav.adoc`](./content/modules/ROOT/nav.adoc) | Module navigation |

## FAQ

If you are facing some issues, please, review our [FAQ.md](./FAQ.md).

## Contributing

We welcome contributions! Please see our [Contributing Guide](./CONTRIBUTING.md) for details on
how to contribute to this project. This project follows the [Contributor Covenant Code of Conduct](./CODE_OF_CONDUCT.md).

### Quick Start

- Clone your new repo and preview locally:

```bash
podman run --rm --name antora -v $PWD:/antora -p 8080:8080 -i -t ghcr.io/juliaaano/antora-viewer
```

On SELinux systems, append `:z` to the volume mount.

- Edit content in `content/modules/ROOT/pages/`
- See the [Content Repository](https://rhpds.github.io/showroom_template_nookbag/modules/content-repo.html) docs for directory layout, Podman Compose with live reload, dev mode, and more.

### Create Content with AI

The [RHDP Skills Marketplace](https://github.com/rhpds/rhdp-skills-marketplace) provides skills for Cursor IDE and Claude Code
that generate labs, demos, and validate content against Red Hat standards.

See the [AI Tools documentation](https://rhpds.github.io/showroom_template_nookbag/modules/content-repo.html#_creating_content_with_ai_tools) for details.
