"""A module defining the third party dependency curl"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive", "http_file")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

def curl_repositories():
    """Defines the curl repository"""

    version = KONG_VAR["CURL"]
    prefix = "curl-" + version
    tag = prefix.replace(".", "_")
    tarball = prefix + ".tar.gz"

    maybe(
        http_archive,
        name = "curl",
        urls = [
            "https://mirror.bazel.build/curl.haxx.se/download/" + tarball,
            "https://curl.se/download/" + tarball,
            "https://github.com/curl/curl/releases/download/%s/%s" % (tag, tarball),
        ],
        type = "tar.gz",
        sha256 = "f98bdb06c0f52bdd19e63c4a77b5eb19b243bcbbd0f5b002b9f3cba7295a3a42",
        strip_prefix = prefix,
        build_file = "//build/curl:BUILD.curl.bazel",
    )

def nghttp2_repositories():
    """Defines the nghttp2 repository; used for providing http2 support to curl"""

    version = "1.55.1"
    prefix = "nghttp2-" + version
    tag = "v" + version
    tarball = prefix + ".tar.gz"

    maybe(
        http_archive,
        name = "nghttp2",
        urls = [
            "https://github.com/nghttp2/nghttp2/releases/download/%s/%s" % (tag, tarball),
        ],
        type = "tar.gz",
        sha256 = "e12fddb65ae3218b4edc083501519379928eba153e71a1673b185570f08beb96",
        strip_prefix = prefix,
        build_file = Label("//build/curl:BUILD.nghttp2.bazel"),
    )

def cacerts_repositories():
    """ cacerts bundle pulled from the curl site """

    version = KONG_VAR["CA_CERTS"]

    maybe(
        http_file,
        name = "cacerts-bundle",
        urls = [
            "https://curl.se/ca/cacert-%s.pem" % version,
        ],
        sha256 = "23c2469e2a568362a62eecf1b49ed90a15621e6fa30e29947ded3436422de9b9",
    )
