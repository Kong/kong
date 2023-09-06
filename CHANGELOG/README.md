# CHANGELOG

The CHANGELOG directory is used for individual changelog file practice.
The `kong/CHANGELOG.md` now is deprecated.


## How to add a changelog file for your PR?

1/ Copy the `changelog-template.yaml` file and rename with your PR number or a short message as the filename. For example, `11279.yaml`, `introduce-a-new-changelog-system.yaml`. (Prefer using PR number as it's already unique and wouldn't introduce conflict)

2/ Fill out the changelog template.


The description of the changelog file field, please follow the `schema.json` for more details.

- message: Message of the changelog
- type: Changelog type. (`feature`, `bugfix`, `dependency`, `deprecation`, `breaking_change`)
- scope: Changelog scope. (`Core`, `Plugin`, `PDK`, `Admin API`, `Performance`, `Configuration`, `Clustering`)
- prs: List of associated GitHub PRs
- issues: List of associated GitHub issues
- jiras: List of associated Jira tickets for internal track

Sample 1
```yaml
message: Introduce the request id as core feature.
type: feat
scope: Core
prs:
  - 11308
```

Sample 2
```yaml
message: Fix response body gets repeated when `kong.response.get_raw_body()` is called multiple times in a request lifecycle.
type: bugfix
scope: PDK
prs:
  - 11424
jiras:
  - "FTI-5296"
```


## changelog command

The `changelog` command tool provides `preview`, and `release` commands.

### Prerequisites

You can skip this part if you're at Kong Bazel virtual env.

Install luajit

Install luarocks libraries

```
luarocks install penlight --local
luarocks install lyaml --local
```

### Usage

```shell
$ ./changelog -h

Usage: changelog <command> [options]

Commands:
  release <version>                  release a release note based on the files in the CHANGELOG/unreleased directory.
  preview <version>                  preview a release note based on the files in the CHANGELOG/unreleased directory.

Options:
  -h, --help                         display help for command
  --from      (default unreleased)   folder of changelog entries, default unreleased

Examples:
  changelog preview 1.0.0
  changelog release 1.0.0
  changelog preview 1.0.0 --from 1.0.0   # preview a release note 1.0.0 based on the files in the 1.0.0 directory
  changelog release 1.0.0 --from 1.0.0   # release a release note 1.0.0 based on the files in the 1.0.0 directory, aka re-generate
```

**Preview a release note**
```shell
./changelog preview 1.0.0
```

**Release a release note**
```shell
./changelog release 1.0.0
```
