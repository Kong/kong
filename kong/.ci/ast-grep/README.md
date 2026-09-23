# ast-grep

`ast-grep` is a tool for querying source code in a (relatively)
language-agnostic manner. It allows us to write lint rules that target patterns
that are specific to our codebase and therefore not covered by tools like
`luacheck`.

## Installing ast-grep

See the [installation docs](https://ast-grep.github.io/guide/quick-start.html#installation)
for guidance.


## Crafting a New Lint Rule

The workflow for writing a new lint rule looks like this:

1. Draft your rule at `.ci/ast-grep/rules/${name}.yml`
    * Use `ast-grep scan --filter ${name} [paths...]` to evaluate your rule's behavior
2. Write tests for the rule in `.ci/ast-grep/tests/${name}-test.yml`
    * Make sure to fill out several `valid` and `invalid` code snippets
    * Use `ast-grep test --interactive`* to test the rule
3. `git add .gi/ast-grep && git commit ...`

\* `ast-grep test` uses a file snapshot testing pattern. Almost any time a rule
or test is created/modified, the snapshots must be updated. The `--interactive`
flag for `ast-grep test` will prompt you to accept these updates. The snapshots
provide very granular testing for rule behavior, but for many cases where we
just care about whether or not a rule matches a certain snippet of code, they
can be overkill. Use `ast-grep --update-all` to automatically accept and save
new snapshots.

## CI

`ast-grep` is executed in the ([ast-grep lint
workflow](/.github/workflows/ast-grep.yml)). In addition to running the linter,
this workflow also performs self-tests and ensures that all existing rules are
well-formed and have tests associated with them.

### Links

* [ast-grep website and documentation](https://ast-grep.github.io)
* [ast-grep source code](https://github.com/ast-grep/ast-grep)
