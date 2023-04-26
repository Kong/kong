
from globmatch import glob_match

from main import FileInfo
from expect import ExpectSuite
from suites import arm64_suites


def transform(f: FileInfo):
    # XXX: libxslt uses libtool and it injects some extra rpaths
    # we only care about the kong library rpath so removing it here
    # until we find a way to remove the extra rpaths from it
    # It should have no side effect as the extra rpaths are long random
    # paths created by bazel.

    if glob_match(f.path, ["**/kong/lib/libxslt.so*", "**/kong/lib/libexslt.so*", "**/kong/lib/libjq.so*"]):
        if f.rpath and "/usr/local/kong/lib" in f.rpath:
            f.rpath = "/usr/local/kong/lib"
        elif f.runpath and "/usr/local/kong/lib" in f.runpath:
            f.runpath = "/usr/local/kong/lib"
        # otherwise remain unmodified

    # XXX: boringssl also hardcodes the rpath during build; normally library
    # loads libssl.so also loads libcrypto.so so we _should_ be fine.
    # we are also replacing boringssl with openssl 3.0 for FIPS for not fixing this for now
    if glob_match(f.path, ["**/kong/lib/libssl.so.1.1"]):
        if f.runpath and "boringssl_fips/build/crypto" in f.runpath:
            f.runpath = "<removed in manifest>"
        elif f.rpath and "boringssl_fips/build/crypto" in f.rpath:
            f.rpath = "<removed in manifest>"


# https://repology.org/project/glibc/versions
# TODO: libstdc++ verions
targets = {
    "alpine-amd64": ExpectSuite(
        name="Alpine Linux (amd64)",
        manifest="fixtures/alpine-amd64.txt",
        use_rpath=True,
    ),
    "amazonlinux-2-amd64": ExpectSuite(
        name="Amazon Linux 2 (amd64)",
        manifest="fixtures/amazonlinux-2-amd64.txt",
        use_rpath=True,
        libc_max_version="2.26",
    ),
    "amazonlinux-2-arm64": ExpectSuite(
        name="Amazon Linux 2 (arm64)",
        manifest="fixtures/amazonlinux-2-arm64.txt",
        use_rpath=True,
        libc_max_version="2.26",
        extra_tests=[arm64_suites],
    ),
    "el7-amd64": ExpectSuite(
        name="Redhat 7 (amd64)",
        manifest="fixtures/el7-amd64.txt",
        use_rpath=True,
        libc_max_version="2.17",
    ),
    "el8-amd64-fips": ExpectSuite(
        name="Redhat 8 (amd64) FIPS",
        manifest="fixtures/el8-amd64-fips.txt",
        use_rpath=True,
        fips=True,
        libc_max_version="2.28",
    ),
    "ubuntu-18.04-amd64": ExpectSuite(
        name="Ubuntu 18.04 (amd64)",
        manifest="fixtures/ubuntu-18.04-amd64.txt",
        libc_max_version="2.27",
    ),
    "ubuntu-20.04-amd64": ExpectSuite(
        name="Ubuntu 20.04 (amd64)",
        manifest="fixtures/ubuntu-20.04-amd64.txt",
        libc_max_version="2.30",
    ),
    "ubuntu-20.04-amd64-fips": ExpectSuite(
        name="Ubuntu 20.04 (amd64) FIPS",
        manifest="fixtures/ubuntu-20.04-amd64-fips.txt",
        fips=True,
        libc_max_version="2.30",
    ),
    "ubuntu-22.04-amd64": ExpectSuite(
        name="Ubuntu 22.04 (amd64)",
        manifest="fixtures/ubuntu-22.04-amd64.txt",
        libc_max_version="2.35",
    ),
    "ubuntu-22.04-amd64-fips": ExpectSuite(
        name="Ubuntu 22.04 (amd64) FIPS",
        manifest="fixtures/ubuntu-22.04-amd64-fips.txt",
        fips=True,
        libc_max_version="2.35",
    ),
    "ubuntu-22.04-arm64": ExpectSuite(
        name="Ubuntu 22.04 (arm64)",
        manifest="fixtures/ubuntu-22.04-arm64.txt",
        libc_max_version="2.35",
        extra_tests=[arm64_suites],
    ),
}
