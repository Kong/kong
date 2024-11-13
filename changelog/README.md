# Setup

Download binary `changelog 0.0.2` from [Kong/gateway-changelog](https://github.com/Kong/gateway-changelog/releases),
or [release-helper](https://github.com/outsinre/release-helper/blob/main/changelog),
and add it to environment variable `PATH`.

```bash
~ $ PATH="/path/to/changelog:$PATH"

~ $ changelog
changelog version 0.0.2
```

Ensure `GITHUB_TOKEN` is set in your environment.

```bash
~ $ echo $GITHUB_TOKEN
```

# Create changelog PR

The command will create a new changelog PR or update an existing one.
Please repeat the command if functional PRs with changelog are merged
after the creation or merge of the changelog PR.

The command depends on tools like `curl`, `jq`, etc., and will refuse to
 create or update changelog PR if any of the tools is not satisfied.

```bash
~ $ pwd
/Users/zachary/workspace/kong/changelog

~ $ make BASE_BRANCH="release/3.6.x" VERSION="3.6.0"
```

The arguments are clarified as below.

1. `BASE_BRANCH`: the origin branch that the changelog PR is created from. It
    is also the merge base.

    The local repo does not have to be on the base branch.
2. `VERSION`: the release version number we are creating the changelog PR for.

   It can be arbitrary strings as long as you know what you are doing (e.g. for
   test purpose)
3. `DEBUG`: shows debug output. Default to `false`.

# Verify Development PRs

Given two arbitrary revisions, list commits, PRs, PRs without changelog
and PRs without CE2EE.

If a CE PR has neither the 'cherry-pick kong-ee' label nor
has cross-referenced EE PRs with 'cherry' in the title,
it is HIGHLY PROBABLY not synced to EE. This is only experimental
as developers may not follow the CE2EE guideline.
However, it is a quick shortcut for us to validate the majority of CE PRs.

Show the usage.

```bash
~ $ pwd
/Users/zachary/workspace/kong

~ $ changelog/verify-prs -h
Version: 0.1
 Author: Zachary Hu (zhucac AT outlook.com)
 Script: Compare between two revisions (e.g. tags and branches), and output
         commits, PRs, PRs without changelog and CE PRs without CE2EE (experimental).

         A PR should have an associated YML file under 'changelog/unreleased', otherwise
         it is printed for verification.

         Regarding CE2EE, if a CE PR has any cross-referenced EE PRs, it is regarded synced
         to EE. If strict mode is enabled, associated EE PRs must contain keyword 'cherry'
         in the title. If a CE PR is labelled with 'cherry-pick kong-ee', it is regarded synced
         to EE. If a CE PR is not synced to EE, it is printed for verification.

  Usage: changelog/verify-prs -h

         -v, --verbose       Print debug info.

         --strict-filter     When checking if a CE PR is synced to EE,
                             more strict filters are applied.

         --safe-mode         When checking if a CE PR is synced to EE,
                             check one by one. This overrides '--bulk'.

         --bulk N            Number of jobs ran concurrency. Default is '5'.
                             Adjust this value to your CPU cores.

Example:
         changelog/verify-prs --org-repo kong/kong --base-commit 3.4.2 --head-commit 3.4.3 [--strict-filter] [--bulk 5] [--safe-mode] [-v]

         ORG_REPO=kong/kong BASE_COMMIT=3.4.2 HEAD_COMMIT=3.4.3 changelog/verify-prs
```

Run the script. Both `--base-commit` and `--head-commit` can be set to branch names.

```bash
~ $ pwd
/Users/zachary/workspace/kong

~ $ changelog/verify-prs --org-repo kong/kong --base-commit 3.4.0 --head-commit 3.5.0
Org Repo: kong/kong
Base Commit: 3.4.0
Head Commit: 3.5.0

comparing between '3.4.0' and '3.5.0'
number of commits: 280
number of pages: 6
commits per page: 50

PRs:
https://github.com/Kong/kong/pull/7414
...

PRs without changelog:
https://github.com/Kong/kong/pull/7413
...

PRs without 'cherry-pick kong-ee' label:
https://github.com/Kong/kong/pull/11721
...

PRs without cross-referenced EE PRs:
https://github.com/Kong/kong/pull/11304
...

Commits: /var/folders/wc/fnkx5qmx61l_wx5shysmql5r0000gn/T/outputXXX.JEkGD8AO/commits.txt
PRs: /var/folders/wc/fnkx5qmx61l_wx5shysmql5r0000gn/T/outputXXX.JEkGD8AO/prs.txt
PRs without changelog: /var/folders/wc/fnkx5qmx61l_wx5shysmql5r0000gn/T/outputXXX.JEkGD8AO/prs_no_changelog.txt
CE PRs without cherry-pick label: /var/folders/wc/fnkx5qmx61l_wx5shysmql5r0000gn/T/outputXXX.JEkGD8AO/prs_no_cherrypick_label.txt
CE PRs without referenced EE cherry-pick PRs: /var/folders/wc/fnkx5qmx61l_wx5shysmql5r0000gn/T/outputXXX.JEkGD8AO/prs_no_cross_reference.txt

Remeber to remove /var/folders/wc/fnkx5qmx61l_wx5shysmql5r0000gn/T/outputXXX.JEkGD8AO
```
