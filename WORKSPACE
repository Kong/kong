workspace(name = "kong")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "bazel_skylib",
    sha256 = "bc283cdfcd526a52c3201279cda4bc298652efa898b10b4db0837dc51652756f",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.7.1/bazel-skylib-1.7.1.tar.gz",
        "https://github.com/bazelbuild/bazel-skylib/releases/download/1.7.1/bazel-skylib-1.7.1.tar.gz",
    ],
)

load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")

bazel_skylib_workspace()

http_archive(
    name = "bazel_features",
    sha256 = "ba1282c1aa1d1fffdcf994ab32131d7c7551a9bc960fbf05f42d55a1b930cbfb",
    strip_prefix = "bazel_features-1.15.0",
    url = "https://github.com/bazel-contrib/bazel_features/releases/download/v1.15.0/bazel_features-v1.15.0.tar.gz",
)

load("@bazel_features//:deps.bzl", "bazel_features_deps")

bazel_features_deps()

http_archive(
    name = "rules_foreign_cc",
    patch_args = ["-p1"],
    patches = [
        "//build:patches/01-revert-LD-environment.patch",
        "//build:patches/02-revert-Reduce-build-times-especially-on-windows.patch",
    ],
    sha256 = "a2e6fb56e649c1ee79703e99aa0c9d13c6cc53c8d7a0cbb8797ab2888bbc99a3",
    strip_prefix = "rules_foreign_cc-0.12.0",
    url = "https://github.com/bazelbuild/rules_foreign_cc/releases/download/0.12.0/rules_foreign_cc-0.12.0.tar.gz",
)

load("@rules_foreign_cc//foreign_cc:repositories.bzl", "rules_foreign_cc_dependencies")

# This sets up some common toolchains for building targets. For more details, please see
# https://bazelbuild.github.io/rules_foreign_cc/0.9.0/flatten.html#rules_foreign_cc_dependencies
rules_foreign_cc_dependencies(
    register_built_tools = False,  # don't build toolchains like make
    register_default_tools = True,  # register cmake and ninja that are managed by bazel
    register_preinstalled_tools = True,  # use preinstalled toolchains like make
)

http_archive(
    name = "rules_rust",
    integrity = "sha256-JLN47ZcAbx9wEr5Jiib4HduZATGLiDgK7oUi/fvotzU=",
    urls = ["https://github.com/bazelbuild/rules_rust/releases/download/0.42.1/rules_rust-v0.42.1.tar.gz"],
)

load("//build:kong_bindings.bzl", "load_bindings")

load_bindings(name = "kong_bindings")

load("//build/openresty:repositories.bzl", "openresty_repositories")

openresty_repositories()

# [[ BEGIN: must happen after any Rust repositories are loaded
load("//build/kong_crate:deps.bzl", "kong_crate_repositories")

kong_crate_repositories(
    cargo_home_isolated = False,
    cargo_lockfile = "//:Cargo.Bazel.lock",
    lockfile = "//:Cargo.Bazel.lock.json",
)

load("//build/kong_crate:crates.bzl", "kong_crates")

kong_crates()
## END: must happen after any Rust repositories are loaded ]]

load("//build/nfpm:repositories.bzl", "nfpm_repositories")

nfpm_repositories()

load("@simdjson_ffi//build:repos.bzl", "simdjson_ffi_repositories")

simdjson_ffi_repositories()

load("//build:repositories.bzl", "build_repositories")

build_repositories()

load("//build/toolchain:repositories.bzl", "toolchain_repositories")

toolchain_repositories()

load("//build/toolchain:managed_toolchain.bzl", "register_all_toolchains")

register_all_toolchains()
