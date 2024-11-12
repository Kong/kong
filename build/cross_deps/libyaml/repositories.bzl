"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def libyaml_repositories():
    """Defines the libyaml repository"""

    # NOTE: do not bump the following version, see build/cross_deps/README.md for detail.
    http_archive(
        name = "cross_deps_libyaml",
        url = "https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz",
        sha256 = "c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4",
        strip_prefix = "yaml-0.2.5",
        build_file = "//build/cross_deps/libyaml:BUILD.libyaml.bazel",
    )
