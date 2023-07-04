"""A module defining the third party dependency OpenSSL"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def openssl_fips_repositories():
    version = KONG_VAR["OPENSSL_FIPS_PROVIDER"]
    version_github = version.replace(".", "_")

    maybe(
        http_archive,
        name = "openssl_fips",
        build_file = "//build/ee/openssl_fips:BUILD.bazel",
        sha256 = "6c13d2bf38fdf31eac3ce2a347073673f5d63263398f1f69d0df4a41253e4b3e",
        strip_prefix = "openssl-" + version,
        urls = [
            "https://www.openssl.org/source/openssl-" + version + ".tar.gz",
            "https://github.com/openssl/openssl/archive/OpenSSL_" + version_github + ".tar.gz",
        ],
    )
