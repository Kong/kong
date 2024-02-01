"""A module defining the third party dependency OpenSSL"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def openssl_repositories():
    version = KONG_VAR["OPENSSL"]
    version_github = version.replace(".", "_")
    parts = version.split(".")
    major_minor_version = ".".join(parts[:2])

    maybe(
        http_archive,
        name = "openssl",
        build_file = "//build/openresty/openssl:BUILD.bazel",
        sha256 = "83c7329fe52c850677d75e5d0b0ca245309b97e8ecbcfdc1dfdc4ab9fac35b39",
        strip_prefix = "openssl-" + version,
        urls = [
            "https://www.openssl.org/source/openssl-" + version + ".tar.gz",
            "https://www.openssl.org/source/old/" + major_minor_version + "/openssl-" + version + ".tar.gz",
            "https://github.com/openssl/openssl/releases/download/openssl-" + version + "/openssl-" + version + ".tar.gz",
            "https://github.com/openssl/openssl/archive/OpenSSL_" + version_github + ".tar.gz",
        ],
    )
