"""A module defining the third party dependency OpenSSL"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def openssl_repositories():
    version = KONG_VAR["OPENSSL"]

    maybe(
        http_archive,
        name = "openssl",
        build_file = "//build/openresty/openssl:BUILD.bazel",
        sha256 = "840af5366ab9b522bde525826be3ef0fb0af81c6a9ebd84caa600fea1731eee3",
        strip_prefix = "openssl-" + version,
        urls = [
            "https://www.openssl.org/source/openssl-" + version + ".tar.gz",
            "https://github.com/openssl/openssl/releases/download/openssl-" + version + "/openssl-" + version + ".tar.gz",
        ],
    )
