**Repository**: {{site.repo}}

Make sure you have all the required dependencies installed, and that you understand how the Makefile works.

Please follow these formatting guidelines:

* Lua indent is 2 spaces
* Disable "auto-format on save" to prevent unnecessary format changes. This makes reviews much harder as it generates unnecessary formatting changes. If your IDE supports formatting only modified chunks, that is fine to do.

Follow the instructions in the [repo's README]({{site.repo}}) to setup your development environment.

Before submitting your changes, run the linter:

```
make lint
```

And the test suite to make sure that nothing is broken:

```bash
make test-all
```
