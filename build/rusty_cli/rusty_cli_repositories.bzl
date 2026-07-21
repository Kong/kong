"""A module defining the third party dependency rusty-cli.

rusty-cli is a native (Rust) drop-in replacement for OpenResty's Perl
resty-cli launcher. It is compiled from source at RPM-build time and
overwrites openresty/bin/resty in the //build:kong tree so the runtime
image no longer needs a Perl interpreter. See ADR-0007 in apip-parent.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def rusty_cli_repositories():
    version = KONG_VAR["RUSTY_CLI"]
    maybe(
        http_archive,
        name = "rusty_cli",
        build_file = "//build/rusty_cli:BUILD.rusty_cli.bazel",
        sha256 = KONG_VAR["RUSTY_CLI_SHA256"],
        strip_prefix = "rusty-cli-" + version,
        urls = [
            "https://github.com/flrgh/rusty-cli/archive/refs/tags/v" + version + ".tar.gz",
        ],
    )
