"""A module defining the third party dependency OpenResty"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def nfpm_repositories():
    maybe(
        http_archive,
        name = "nfpm",
        sha256 = "a629d7d8a3f0b7fa2bdcf5eab9ee2e0b438dbda2171b3adc509c126841f67f71",
        url = "https://github.com/goreleaser/nfpm/releases/download/v2.22.2/nfpm_2.22.2_Linux_x86_64.tar.gz",
        build_file = "//build/nfpm:BUILD.bazel",
    )
