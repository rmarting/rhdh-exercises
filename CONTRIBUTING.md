# Contributing to Red Hat Developer Hub Workshop

Thank you for your interest in contributing to the Red Hat Developer Hub Workshop! This document
provides guidelines and instructions for contributing to this project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
- [Development Setup](#development-setup)
- [Contribution Workflow](#contribution-workflow)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)
- [Documentation Guidelines](#documentation-guidelines)
- [Code and Configuration Standards](#code-and-configuration-standards)
- [Commit Message Guidelines](#commit-message-guidelines)

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). All
contributors are expected to follow it. Please be respectful, inclusive, and professional in all
interactions.

By participating in this project, you agree to abide by its terms. Instances of abusive,
harassing, or otherwise unacceptable behavior may be reported by contacting the project
maintainers.

## How to Contribute

There are many ways to contribute to this project:

- **Reporting bugs**: If you find a bug, please open an issue describing the problem
- **Suggesting enhancements**: Share your ideas for new features or improvements
- **Improving documentation**: Help make the documentation clearer and more comprehensive
- **Adding new exercises**: Contribute new workshop exercises or configurations
- **Fixing issues**: Submit pull requests to fix bugs or implement enhancements
- **Reviewing pull requests**: Help review and test contributions from others

## Development Setup

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:

   ```bash
   git clone https://github.com/YOUR_USERNAME/rhdh-exercises.git
   cd rhdh-exercises
   ```
3. **Add the upstream repository** as a remote:

   ```bash
   git remote add upstream https://github.com/rmarting/rhdh-exercises.git
   ```
4. **Create a branch** for your changes:

   ```bash
   git checkout -b your-feature-branch
   ```

## Contribution Workflow

1. **Keep your fork updated**:

   ```bash
   git fetch upstream
   git checkout main
   git merge upstream/main
   ```

2. **Create a feature branch** from `main`:

   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/your-bug-fix
   ```

3. **Make your changes** following the project's standards

4. **Test your changes** to ensure they work as expected

5. **Commit your changes** with clear, descriptive commit messages using emoji patterns (see
   [Commit Message Guidelines](#commit-message-guidelines))

6. **Push to your fork**:

   ```bash
   git push origin your-feature-branch
   ```

7. **Open a Pull Request** on GitHub

## Pull Request Process

### Before Submitting

- [ ] Ensure your code follows the project's style guidelines
- [ ] Test your changes thoroughly
- [ ] Update documentation if needed
- [ ] Check that all YAML files are valid
- [ ] Ensure your branch is up to date with `main`

### Pull Request Guidelines

1. **Use a clear, descriptive title** that summarizes the change
2. **Provide a detailed description** of what the PR does and why
3. **Reference related issues** using keywords like "Fixes #123" or "Closes #456"
4. **Include screenshots or examples** if applicable
5. **Keep PRs focused** - one feature or fix per pull request
6. **Ensure all checks pass** before requesting review

### PR Template

When opening a pull request, please use the [Pull Request Template](.github/pull_request_template.md)
that will be automatically populated when you create a new PR. The template includes:

- Description of changes
- Type of change selection
- Testing information
- Checklist of requirements
- Related issues reference
- Screenshots/examples section

## Reporting Issues

We use GitHub issue templates to help structure issue reports. When creating a new issue, you'll
be prompted to choose from the following templates:

### Issue Templates

- **[Bug Report](.github/ISSUE_TEMPLATE/bug_report.md)**: Use this template when reporting bugs
  or unexpected behavior
- **[Feature Request](.github/ISSUE_TEMPLATE/feature_request.md)**: Use this template to suggest
  new features or enhancements
- **[Question](.github/ISSUE_TEMPLATE/question.md)**: Use this template for questions or
  discussions

Each template includes relevant fields to help provide the necessary information. Please fill out
the template as completely as possible to help us understand and address your issue.

### Issue Labels

Issues are automatically labeled based on the template used. Additional labels may be applied by
maintainers:

- `bug`: Something isn't working
- `enhancement`: New feature or request
- `documentation`: Documentation improvements
- `question`: Questions or discussions
- `help wanted`: Extra attention is needed
- `good first issue`: Good for newcomers

## Documentation Guidelines

### Markdown Standards

- Use proper heading hierarchy (H1 → H2 → H3)
- Include a table of contents for longer documents
- Use code blocks with syntax highlighting:
  - Use `bash` for bash scripts and shell commands
  - Use `yaml` for YAML configuration files
  - Use `text` for plain text output or logs
  - Use appropriate language identifiers for other code types
- Add alt text to images
- Keep line length reasonable (100 characters)
- Use consistent formatting throughout

### Documentation Structure

- **README.md**: Main project overview and getting started
- **README-*.md**: Specific topic documentation
- **CONTRIBUTING.md**: This file
- **CODE_OF_CONDUCT.md**: Code of Conduct
- **LICENSE**: License information

### Writing Style

- Write clearly and concisely
- Use active voice when possible
- Include examples where helpful
- Keep instructions step-by-step and numbered
- Add context and explanations, not just commands

## Code and Configuration Standards

### YAML Files

- Use consistent indentation (2 spaces recommended)
- Validate YAML syntax before committing
- Follow OpenShift resource naming conventions
- Include comments for complex configurations
- Keep configuration files organized by purpose

### File Organization

- Group related files in appropriate directories
- Use descriptive file names
- Follow existing naming conventions
- Keep configuration files in `custom-app-config-gitlab/` or `lab-prep/` as appropriate

### Best Practices

- **Idempotency**: Configurations should be repeatable
- **Documentation**: Comment complex configurations
- **Consistency**: Follow existing patterns in the repository
- **Validation**: Ensure all YAML files are valid before committing

## Commit Message Guidelines

We use emoji-based commit messages for fun and clarity! Each commit message should start with an
emoji that represents the type of change, following gitmoji patterns.

### Format

```
<emoji> <subject>

<body>
```

### Emoji Guide

Choose the appropriate emoji based on your change:

- ✨ `:sparkles:` - **New feature**: Adding a new exercise or feature
- 🐛 `:bug:` - **Bug fix**: Fixing a bug or issue
- 📝 `:memo:` - **Documentation**: Writing or updating documentation
- 🔧 `:wrench:` - **Configuration**: Configuration changes
- ⬆️ `:arrow_up:` - **Dependencies**: Upgrading dependencies
- ⬇️ `:arrow_down:` - **Dependencies**: Downgrading dependencies
- ♻️ `:recycle:` - **Refactoring**: Code restructuring
- 🧪 `:test_tube:` - **Tests**: Adding or updating tests

### Examples

```
✨ Add GitLab authentication configuration

Add support for GitLab OAuth authentication in the RHDH instance configuration. Includes provider
setup and user mapping.

Fixes #123
```

```
📝 Update README with topology diagram

Add topology diagram and improve installation instructions.
```

```
🐛 Fix RBAC policy configuration

Fix incorrect namespace reference in RBAC policy configmap.
```

```
🎨 Improve YAML formatting in lab-prep directory

Standardize indentation and add helpful comments to configuration files.
```

```
🚀 Deploy new orchestrator exercise configuration

Add complete orchestrator setup with workflow examples.
```

### Guidelines

- **Always start with an emoji** - it's the first character of your commit message
- Use imperative mood ("Add feature" not "Added feature")
- Keep subject line under 72 characters
- Capitalize the subject line (after the emoji)
- Don't end subject with a period
- Separate subject from body with a blank line
- Wrap body at 100 characters
- Use body to explain what and why, not how
- Have fun with it! 🎉

## Review Process

1. **Automated checks** will run on your PR
2. **Maintainers will review** your contribution
3. **Feedback may be requested** - please respond promptly
4. **Changes may be requested** - update your PR accordingly
5. **Once approved**, a maintainer will merge your PR

## Questions?

If you have questions about contributing:

- Open an issue with the `question` label
- Check existing issues and discussions
- Review the documentation files

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0,
the same license that covers the project.

Thank you for contributing to the Red Hat Developer Hub Workshop! 🎉
