
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

    if glob_match(f.path, ["**/kong/lib/libxslt.so*", "**/kong/lib/libexslt.so*"]):
        if f.rpath and "/usr/local/kong/lib" in f.rpath:
            f.rpath = "/usr/local/kong/lib"
        elif f.runpath and "/usr/local/kong/lib" in f.runpath:
            f.runpath = "/usr/local/kong/lib"
        # otherwise remain unmodified


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
    "alpine-arm64": ExpectSuite(
        name="Alpine Linux (arm64)",
        manifest="fixtures/alpine-arm64.txt",
        use_rpath=True,
        extra_tests=[arm64_suites],
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
    "amazonlinux-2023-amd64": ExpectSuite(
        name="Amazon Linux 2023 (amd64)",
        manifest="fixtures/amazonlinux-2023-amd64.txt",
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
    "el8-amd64": ExpectSuite(
        name="Redhat 8 (amd64)",
        manifest="fixtures/el8-amd64.txt",
        use_rpath=True,
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
    "ubuntu-22.04-amd64": ExpectSuite(
        name="Ubuntu 22.04 (amd64)",
        manifest="fixtures/ubuntu-22.04-amd64.txt",
        libc_max_version="2.35",
        # gcc 11.2.0
        libcxx_max_version="3.4.29",
        cxxabi_max_version="1.3.13",
    ),
    "ubuntu-22.04-arm64": ExpectSuite(
        name="Ubuntu 22.04 (arm64)",
        manifest="fixtures/ubuntu-22.04-arm64.txt",
        libc_max_version="2.35",
        # gcc 11.2.0
        libcxx_max_version="3.4.29",
        cxxabi_max_version="1.3.13",
        extra_tests=[arm64_suites],
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
