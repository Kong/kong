"""A module defining the third party dependency OpenSSL"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def openssl_repositories():
    version = KONG_VAR["RESTY_OPENSSL_VERSION"]
    version_github = version.replace(".", "_")

    maybe(
        http_archive,
        name = "openssl",
        build_file = "//build/openresty/openssl:BUILD.openssl.bazel",
        sha256 = "8dee9b24bdb1dcbf0c3d1e9b02fb8f6bf22165e807f45adeb7c9677536859d3b",
        strip_prefix = "openssl-" + version,
        urls = [
            "https://www.openssl.org/source/openssl-" + version + ".tar.gz",
            "https://github.com/openssl/openssl/archive/OpenSSL_" + version_github + ".tar.gz",
        ],
    )
