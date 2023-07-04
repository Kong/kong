"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def jq_repositories():
    """Defines the jq repository"""

    version = KONG_VAR["LIBJQ"]

    maybe(
        http_archive,
        name = "jq",
        # Use our own packaged tarball to avoid `autoreconf` during build time, some old distros
        # doesn't have proper autotools versions available.
        # TODO: revert back to official releases once 1.6+ is released.
        url = "https://github.com/Kong/jq/releases/download/jq-" + version + "/jq-" + version + ".tar.gz",
        sha256 = "7f6fe8bdb88f8ce59011f99fdc7a8b8c44af8e9d1c64b868cf4c8617869181fc",
        strip_prefix = "jq-" + version,
        build_file = "//build/ee/jq:BUILD.jq.bazel",
    )
