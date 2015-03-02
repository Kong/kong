**REPOSITORY**: [https://github.com/mashape/kong](https://github.com/mashape/kong)

Make sure you have all the required dependencies installed, and that you understand how the Makefile works.

Please follow these formatting guidelines:

Lua indent is 2 spaces Line width is 140 characters The rest is left to Lua coding standards Disable “auto-format on save” to prevent unnecessary format changes. This makes reviews much harder as it generates unnecessary formatting changes. If your IDE supports formatting only modified chunks that is fine to do.

To create a distribution from the source, simply run:

```bash
cd kong
make dev
```

You will find the newly built development configuration under: ./config.dev/

Before submitting your changes, run the test suite to make sure that nothing is broken, with:

```bash
make test-all
```
