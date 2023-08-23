# CHANGELOG

The CHANGELOG directory is used for individual changelog file practice.
The `kong/CHANGELOG.md` now is deprecated.


## How to add a changelog file for your PR?

1/ Copy the `changelog-template.yaml` file and rename with your PR number or a short message as the filename. For example, `11279.yaml`, `introduce-a-new-changelog-system.yaml`. (Prefer using PR number as it's already unique and wouldn't introduce conflict)

2/ Fill out the changelog template.


The description of the changelog file field, please follow the `schema.json` for more details.

- message: Message of the changelog
- type: Changelog type
- scope: Changelog scope
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

The `changelog` command tool provides `add`, `preview`, and `release` commands.

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
  add <filename> [options]           add a changelog file.
  release <version> [options]        release a release note based on the files in the CHANGELOG/unreleased directory.
  preview <version> [options]        preview a release note based on the files in the CHANGELOG/unreleased directory.

Options:
  -h, --help                         display help for command
  -m, --message (optional string)    changelog message
  -t, --type (optional string)       changelog type
  --folder (string default kong)     which folder under unreleased

Examples:
  changelog add 1.yaml
  changelog preview 1.0.0
  changelog release 1.0.0
```

**Add a changelog file**
```shell
./changelog add 1001.yaml -m 'add a feature' -t feature --folder kong
```

**Preview a release note**
```shell
./changelog preview 1.0.0
```

**Release a release note**
```shell
./changelog release 1.0.0
```
