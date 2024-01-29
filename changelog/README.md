# Setup

Add the `changelog` directory to your environment variable `PATH`.

```bash
~ $ pwd
/Users/zachary/workspace/kong-ee

~ $ cd changelog
~ $ PATH="$(realpath .):$PATH"
```

Enure `golang` is available on your local system.

```bash
~ $ go env
```

Ensure binaries are executable.

```bash
~ $ chmod +x ./changelog

~ $ chmod +x ./verify-prs
```

# Generate changelog

Take EE repo and `3.6.0.0` for example, check the operations below. To enable debug,
add option `DEBUG=true`.

```bash
~ $ pwd
/Users/zachary/workspace/kong-ee

~ $ git fetch --all
~ $ git checkout -b geneerate-3.6.0.0-changelog origin/master

~ $ cd changelog
~ $ make VERSION=3.6.0.0

~ $ git status
~ $ ls 3.6.0.0/3.6.0.0.md

~ $ git add .
~ $ git commit -m "docs(release): genereate 3.6.0.0 changelog"
~ $ git push -u origin HEAD
```

Suppose a new PR is merged after the changelog PR is created, please rerun
`make VERSION=3.6.0.0` to update changelog.

# Verify PRs

Given two arbitrary revisions, list commits, PRs, PRs without changelog and PRs without CE2EE.

If a CE PR has neither the 'cherry-pick kong-ee' label nor has cross-referenced EE PRs with 'cherry'
in the title, it is HIGHLY PROBABLY not synced to EE. This is only experimental as developers may not
follow the CE2EE guideline. However, it is a quick shortcut for us to validate the majority of CE PRs.

Ensure `GITHUB_TOKEN` is set in your environment.

```bash
~ $ echo $GITHUB_TOKEN
```

Run the script. Both `--base-commit` and `--head-commit` can be set to branch names.

```bash
~ $ verify-prs -h
Version: 0.1
 Author: Zachary Hu (zhucac AT outlook.com)
 Script: Compare between two revisions (e.g. tags and branches), and output
         commits, PRs, PRs without changelog and CE PRs without CE2EE (experimental).

         A PR should have an associated YML file under 'unreleased', otherwise
         it is printed for verification.

         Regarding CE2EE, if a CE PR has any cross-referenced EE PRs, it is regarded synced
         to EE. If strict mode is enabled, associated EE PRs must contain keyword 'cherry'
         in the title. If a CE PR is labelled with 'cherry-pick kong-ee', it is regarded synced
         to EE. If a CE PR is not synced to EE, it is printed for verification.

  Usage: verify-prs -h

         -v, --verbose       Print debug info.

         --strict-filter     When checking if a CE PR is synced to EE,
                             more strict filters are applied.

         --safe-mode         When checking if a CE PR is synced to EE,
                             check one by one. This overrides '--bulk'.

         --bulk N            Number of jobs ran concurrency. Default is '5'.
                             Adjust this value to your CPU cores.

         verify-prs --org-repo kong/kong-ee --base-commit 3.4.2.0 --head-commit 3.4.2.1 [--strict-filter] [--bulk 5] [--safe-mode] [-v]

         ORG_REPO=kong/kong-ee BASE_COMMIT=3.4.2.0 HEAD_COMMIT=3.4.2.1 verify-prs

~ $ verify-prs --org-repo kong/kong --base-commit 3.4.0 --head-commit 3.5.0
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
