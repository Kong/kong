# Bazel project for atc-router


To use in other Bazel projects, add the following to your WORKSPACE file:

```python

load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

git_repository(
    name = "resty_protobuf",
    branch = "some-tag",
    remote = "https://github.com/Kong/atc-router",
)

load("@resty_protobuf//build:repos.bzl", "resty_protobuf_repositories")

resty_protobuf_repositories()

load("@resty_protobuf//build:deps.bzl", "resty_protobuf_dependencies")

resty_protobuf_dependencies(cargo_home_isolated = False) # use system `$CARGO_HOME` to speed up builds

load("@resty_protobuf//build:crates.bzl", "resty_protobuf_crates")

resty_protobuf_crates()


```

In your rule, add `resty_protobuf` as dependency:

```python
configure_make(
    name = "openresty",
    # ...
    deps = [
        "@resty_protobuf",
    ],
)
```

When building this library in Bazel, use the `-c opt` flag to ensure optimal performance. The default fastbuild mode produces a less performant binary.