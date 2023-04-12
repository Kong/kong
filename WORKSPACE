workspace(name = "kong")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "bazel_skylib",
    sha256 = "74d544d96f4a5bb630d465ca8bbcfe231e3594e5aae57e1edbf17a6eb3ca2506",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
        "https://github.com/bazelbuild/bazel-skylib/releases/download/1.3.0/bazel-skylib-1.3.0.tar.gz",
    ],
)

load("//build:kong_bindings.bzl", "load_bindings")

load_bindings(name = "kong_bindings")

# TODO: pin rules_foreign_cc back to tag once the following commit is released
foreign_cc_commit_sha = "1023d7ed6b343955f9ffb26437d07bdd97448a02"

http_archive(
    name = "rules_foreign_cc",
    sha256 = "a209c91eaa4178b74cbb420527b58a9846f76d234eb45c093c6d873d5b57e79d",
    strip_prefix = "rules_foreign_cc-" + foreign_cc_commit_sha,
    url = "https://github.com/bazelbuild/rules_foreign_cc/archive/" + foreign_cc_commit_sha + ".zip",
)

load("@rules_foreign_cc//foreign_cc:repositories.bzl", "rules_foreign_cc_dependencies")

# This sets up some common toolchains for building targets. For more details, please see
# https://bazelbuild.github.io/rules_foreign_cc/0.9.0/flatten.html#rules_foreign_cc_dependencies
rules_foreign_cc_dependencies(
    register_built_tools = False,  # don't build toolchains like make
    register_default_tools = True,  # register cmake and ninja that are managed by bazel
    register_preinstalled_tools = True,  # use preinstalled toolchains like make
)

load("//build/openresty:repositories.bzl", "openresty_repositories")

openresty_repositories()

load("//build/nfpm:repositories.bzl", "nfpm_repositories")

nfpm_repositories()

load("@atc_router//build:repos.bzl", "atc_router_repositories")

atc_router_repositories()

load("@atc_router//build:deps.bzl", "atc_router_dependencies")

atc_router_dependencies(cargo_home_isolated = False)  # TODO: set cargo_home_isolated=True for release

load("@atc_router//build:crates.bzl", "atc_router_crates")

atc_router_crates()

load("//build/ee:repositories.bzl", "ee_repositories")

ee_repositories()

load("//build:repositories.bzl", "build_repositories")

build_repositories()

load("//build/toolchain:repositories.bzl", "toolchain_repositories")

toolchain_repositories()

register_toolchains("//build/toolchain:gcc_cross_arm64_toolchain")

register_toolchains("//build/toolchain:gcc_cross_musl_x86_64_toolchain")
