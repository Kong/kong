
from copy import deepcopy

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


# libc:
# - https://repology.org/project/glibc/versions
# GLIBCXX and CXXABI based on gcc version:
# - https://gcc.gnu.org/onlinedocs/libstdc++/manual/abi.html
# - https://repology.org/project/gcc/versions
# TODO: libstdc++ verions
targets = {
    "alpine-amd64": ExpectSuite(
        name="Alpine Linux (amd64)",
        manifest="fixtures/alpine-amd64.txt",
        use_rpath=True,
        # alpine 3.16: gcc 11.2.1
        libcxx_max_version="3.4.29",
        cxxabi_max_version="1.3.13",
    ),
    "amazonlinux-2-amd64": ExpectSuite(
        name="Amazon Linux 2 (amd64)",
        manifest="fixtures/amazonlinux-2-amd64.txt",
        use_rpath=True,
        libc_max_version="2.26",
        # gcc 7.3.1
        libcxx_max_version="3.4.24",
        cxxabi_max_version="1.3.11",
    ),
    "amazonlinux-2022-amd64": ExpectSuite(
        name="Amazon Linux 2022 (amd64)",
        manifest="fixtures/amazonlinux-2022-amd64.txt",
        libc_max_version="2.34",
        # gcc 11.2.1
        libcxx_max_version="3.4.29",
        cxxabi_max_version="1.3.13",
    ),
    "el7-amd64": ExpectSuite(
        name="Redhat 7 (amd64)",
        manifest="fixtures/el7-amd64.txt",
        use_rpath=True,
        libc_max_version="2.17",
        # gcc 4.8.5
        libcxx_max_version="3.4.19",
        cxxabi_max_version="1.3.7",
    ),
    "el8-amd64-fips": ExpectSuite(
        name="Redhat 8 (amd64) FIPS",
        manifest="fixtures/el8-amd64-fips.txt",
        use_rpath=True,
        fips=True,
        libc_max_version="2.28",
        # gcc 8.5.0
        libcxx_max_version="3.4.25",
        cxxabi_max_version="1.3.11",
    ),
    "ubuntu-20.04-amd64": ExpectSuite(
        name="Ubuntu 20.04 (amd64)",
        manifest="fixtures/ubuntu-20.04-amd64.txt",
        libc_max_version="2.30",
        # gcc 9.3.0
        libcxx_max_version="3.4.28",
        cxxabi_max_version="1.3.12",
    ),
    "ubuntu-20.04-amd64-fips": ExpectSuite(
        name="Ubuntu 20.04 (amd64) FIPS",
        manifest="fixtures/ubuntu-20.04-amd64-fips.txt",
        fips=True,
        libc_max_version="2.30",
        # gcc 9.3.0
        libcxx_max_version="3.4.28",
        cxxabi_max_version="1.3.12",
    ),
    "ubuntu-22.04-amd64": ExpectSuite(
        name="Ubuntu 22.04 (amd64)",
        manifest="fixtures/ubuntu-22.04-amd64.txt",
        libc_max_version="2.35",
        # gcc 11.2.0
        libcxx_max_version="3.4.29",
        cxxabi_max_version="1.3.13",
    ),
    "ubuntu-22.04-amd64-fips": ExpectSuite(
        name="Ubuntu 22.04 (amd64) FIPS",
        manifest="fixtures/ubuntu-22.04-amd64-fips.txt",
        fips=True,
        libc_max_version="2.35",
        # gcc 11.2.0
        libcxx_max_version="3.4.29",
        cxxabi_max_version="1.3.13",
    ),
    "debian-10-amd64": ExpectSuite(
        name="Debian 10 (amd64)",
        manifest="fixtures/debian-10-amd64.txt",
        libc_max_version="2.28",
        # gcc 8.3.0
        libcxx_max_version="3.4.25",
        cxxabi_max_version="1.3.11",
    ),
    "debian-11-amd64": ExpectSuite(
        name="Debian 11 (amd64)",
        manifest="fixtures/debian-11-amd64.txt",
        libc_max_version="2.31",
        # gcc 10.2.1
        libcxx_max_version="3.4.28",
        cxxabi_max_version="1.3.12",
    ),
}

# populate arm64 suites from amd64 suites

for target in list(targets.keys()):
    # TODO: no dedicated for amazonlinux-2022 for now
    if target.split("-")[0] not in ("alpine", "ubuntu", "debian", "amazonlinux") or \
        target == "amazonlinux-2022-amd64" or \
        target.endswith("-fips"):
        continue

    e = deepcopy(targets[target])
    e.manifest = e.manifest.replace("-amd64.txt", "-arm64.txt")
    e.name = e.name.replace("(amd64)", "(arm64)")
    e.extra_tests = [arm64_suites]

    targets[target.replace("-amd64", "-arm64")] = e

