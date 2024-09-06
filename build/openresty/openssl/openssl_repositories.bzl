"""A module defining the third party dependency OpenSSL"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def openssl_repositories():
    version = KONG_VAR["OPENSSL"]

    openssl_verion_uri = version
    if version.startswith("3"):
        # for 3.x only use the first two digits
        openssl_verion_uri = ".".join(version.split(".")[:2])

    maybe(
        http_archive,
        name = "openssl",
        build_file = "//build/openresty/openssl:BUILD.bazel",
        sha256 = KONG_VAR["OPENSSL_SHA256"],
        strip_prefix = "openssl-" + version,
        urls = [
            "https://github.com/openssl/openssl/releases/download/openssl-" + version + "/openssl-" + version + ".tar.gz",
            "https://openssl.org/source/old/3.1/openssl-" + version + ".tar.gz",
        ],
    )
