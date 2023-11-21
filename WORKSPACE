workspace(name = "kong")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "bazel_skylib",
    sha256 = "cd55a062e763b9349921f0f5db8c3933288dc8ba4f76dd9416aac68acee3cb94",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-skylib/releases/download/1.5.0/bazel-skylib-1.5.0.tar.gz",
        "https://github.com/bazelbuild/bazel-skylib/releases/download/1.5.0/bazel-skylib-1.5.0.tar.gz",
    ],
)

load("//build:kong_bindings.bzl", "load_bindings")

load_bindings(name = "kong_bindings")

http_archive(
    name = "rules_foreign_cc",
    sha256 = "476303bd0f1b04cc311fc258f1708a5f6ef82d3091e53fd1977fa20383425a6a",
    strip_prefix = "rules_foreign_cc-0.10.1",
    url = "https://github.com/bazelbuild/rules_foreign_cc/archive/refs/tags/0.10.1.tar.gz",
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

load("//build:repositories.bzl", "build_repositories")

build_repositories()

load("//build/toolchain:repositories.bzl", "toolchain_repositories")

toolchain_repositories()

load("//build/toolchain:managed_toolchain.bzl", "register_all_toolchains")

register_all_toolchains()
