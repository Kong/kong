"""# Contributing to Kong :monkey_face:

Hello, and welcome! Whether you are looking for help, trying to report a bug, thinking about getting involved in the project, or about to submit a patch, this document is for you. It serves as both an entry point for newcomers to the community and a guide/reference for contributors and maintainers.

Please review our [Community Pledge](./COMMUNITY_PLEDGE.md) to understand how we work with our open-source contributors.

## Table of Contents

* [Contributing to Kong :monkey_face:](#contributing-to-kong-monkey_face)
    * [Where to seek for help?](#where-to-seek-for-help)
        * [Enterprise Edition](#enterprise-edition)
        * [Community Edition](#community-edition)
    * [Where to report bugs?](#where-to-report-bugs)
    * [Where to submit feature requests?](#where-to-submit-feature-requests)
    * [Contributing](#contributing)
        * [Improving the documentation](#improving-the-documentation)
        * [Proposing a new plugin](#proposing-a-new-plugin)
        * [Submitting a patch](#submitting-a-patch)
            * [Git branches](#git-branches)
            * [Commit atomicity](#commit-atomicity)
            * [Commit message format](#commit-message-format)
                * [Type](#type)
                * [Scope](#scope)
                * [Subject](#subject)
                * [Body](#body)
                * [Footer](#footer)
                * [Examples](#examples)
            * [Static linting](#static-linting)
            * [Writing tests](#writing-tests)
            * [Writing changelog](#writing-changelog)
            * [Writing performant code](#writing-performant-code)
            * [Adding Changelog](#adding-changelog)
        * [Contributor Badge](#contributor-badge)
    * [Code style](#code-style)
        * [Modules](#modules)
        * [Variables](#variables)
        * [Tables](#tables)
        * [Strings](#strings)
        * [Functions](#functions)
        * [Conditional expressions](#conditional-expressions)

## Where to seek for help?

### Enterprise Edition

If you are a Kong Enterprise customer, please contact Enterprise Support by opening a ticket at [https://support.konghq.com](https://support.konghq.com/).

For P1 issues, use the [24/7 Enterprise Support phone line](https://support.konghq.com/hc/en-us/articles/115004921808-Telephone-Support) for immediate assistance, as detailed in your Customer Success Reference Guide.

For sales inquiries, visit [https://konghq.com/kong-enterprise-edition/](https://konghq.com/kong-enterprise-edition/) or contact [sales@konghq.com](mailto:sales@konghq.com).

### Community Edition

For questions regarding the Community Edition, please use [GitHub Discussions](https://github.com/Kong/kong/discussions). You can also join our [Community Slack](http://kongcommunity.slack.com/) for real-time interaction.

**Please avoid opening GitHub issues for general support questions**, as these are reserved for confirmed bug reports.

Our public forum, [Kong Nation](https://discuss.konghq.com), is the ideal place for asking questions, sharing advice, and staying updated with announcements.

## Where to report bugs?

Please [submit an issue](https://github.com/Kong/kong/issues/new/choose) on the GitHub repository. Ensure you follow the issue template and include:
1. A clear summary of the issue.
2. Step-by-step reproduction instructions.
3. The version of Kong being used.
4. Relevant parts of your configuration.

If you have a fix, feel free to propose a patch. See the [Submitting a patch](#submitting-a-patch) section for instructions.

## Where to submit feature requests?

You can [submit an issue](https://github.com/Kong/kong/issues/new/choose) for feature requests. Please provide as much detail as possible. You are also welcome to submit a patch for new features.

## Contributing

Beyond code enhancements and bug fixes, you can contribute by:
- Reporting bugs.
- Assisting other community members on support channels.
- Fixing typos in the code or documentation.
- Providing feedback on proposed features/designs.
- Reviewing Pull Requests.

### Improving the documentation

The documentation at [https://docs.konghq.com](https://docs.konghq.com) is open source and built with [Jekyll](https://jekyllrb.com/). Contributions to correct typos, add examples, or improve clarity are highly welcome. The repository is hosted at [https://github.com/Kong/docs.konghq.com/](https://github.com/Kong/docs.konghq.com/).

### Proposing a new plugin

We generally do not accept new plugins into this repository. Specialized functionality should reside in separate repositories. If you are interested in developing a plugin, start by reading the [Plugin Development Guide](https://docs.konghq.com/latest/plugin-development).

If you wish to distribute your plugin, host it on a public repository and distribute it via [LuaRocks](https://luarocks.org/search?q=kong). To increase visibility:
1. Add your plugin to the [Kong Hub](https://docs.konghq.com/hub/).
2. Post an announcement in the [Kong Nation forum](https://discuss.konghq.com/c/announcements).

### Submitting a patch

For bug fixes or minor features, please open a Pull Request. For larger features, discuss your approach in [GitHub Discussions](https://github.com/Kong/kong/discussions) first.

Before submitting, ensure:
- Your commit history is clean and atomic.
- You have rebased your work on the base branch to ensure a linear history.
- Static linting (`make lint`) passes.
- Tests (`make test`) pass.
- **Do not** manually update `CHANGELOG.md`; it is automatically managed during the release process.

#### Git branches
Please use the following naming convention for branches:
- `feat/`: New features
- `fix/`: Bug fixes
- `tests/`: Test suite changes
- `refactor/`: Refactoring (no behavior changes)
- `style/`: Style adjustments
- `docs/`: Documentation updates
- `chore/`: Maintenance (non-functional changes)
- `perf/`: Performance improvements

#### Commit message format
We follow [conventional-commits](https://www.conventionalcommits.org/en/v1.0.0/):
