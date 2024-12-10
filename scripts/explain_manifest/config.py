from copy import deepcopy

from globmatch import glob_match

from main import FileInfo
from expect import ExpectSuite
from suites import common_suites, libc_libcpp_suites, arm64_suites, docker_suites


def transform(f: FileInfo):
    # XXX: libxslt uses libtool and it injects some extra rpaths
    # we only care about the kong library rpath so removing it here
    # until we find a way to remove the extra rpaths from it
    # It should have no side effect as the extra rpaths are long random
    # paths created by bazel.

    if glob_match(f.path, ["**/kong/lib/libxslt.so*", "**/kong/lib/libexslt.so*"]):
        expected_rpath = "/usr/local/kong/lib"
        if f.rpath and expected_rpath in f.rpath:
            f.rpath = expected_rpath
        elif f.runpath and expected_rpath in f.runpath:
            f.runpath = expected_rpath
        # otherwise remain unmodified

    if f.path.endswith("/modules/ngx_wasmx_module.so"):
        expected_rpath = "/usr/local/openresty/luajit/lib:/usr/local/kong/lib:/usr/local/openresty/lualib"
        if f.rpath and expected_rpath in f.rpath:
            f.rpath = expected_rpath
        elif f.runpath and expected_rpath in f.runpath:
            f.runpath = expected_rpath
        # otherwise remain unmodified


# libc:
# - https://repology.org/project/glibc/versions
# GLIBCXX and CXXABI based on gcc version:
# - https://gcc.gnu.org/onlinedocs/libstdc++/manual/abi.html
# - https://repology.org/project/gcc/versions
# TODO: libstdc++ verions
targets = {
    "amazonlinux-2-amd64": ExpectSuite(
        name="Amazon Linux 2 (amd64)",
        manifest="fixtures/amazonlinux-2-amd64.txt",
        use_rpath=True,
        tests={
            common_suites: {
                "skip_libsimdjson_ffi": True,
            },
            libc_libcpp_suites: {
                "libc_max_version": "2.26",
                # gcc 7.3.1
                "libcxx_max_version": "3.4.24",
                "cxxabi_max_version": "1.3.11",
            },
        },
    ),
    "amazonlinux-2023-amd64": ExpectSuite(
        name="Amazon Linux 2023 (amd64)",
        manifest="fixtures/amazonlinux-2023-amd64.txt",
        tests={
            common_suites: {
                "libxcrypt_no_obsolete_api": True,
            },
            libc_libcpp_suites: {
                "libc_max_version": "2.34",
                # gcc 11.2.1
                "libcxx_max_version": "3.4.29",
                "cxxabi_max_version": "1.3.13",
            },
        },
    ),
    "el8-amd64": ExpectSuite(
        name="Redhat 8 (amd64)",
        manifest="fixtures/el8-amd64.txt",
        use_rpath=True,
        tests={
            common_suites: {},
            libc_libcpp_suites: {
                "libc_max_version": "2.28",
                # gcc 8.5.0
                "libcxx_max_version": "3.4.25",
                "cxxabi_max_version": "1.3.11",
            },
        },
    ),
    "el9-amd64": ExpectSuite(
        name="Redhat 8 (amd64)",
        manifest="fixtures/el9-amd64.txt",
        use_rpath=True,
        tests={
            common_suites: {
                "libxcrypt_no_obsolete_api": True,
            },
            libc_libcpp_suites: {
                "libc_max_version": "2.34",
                # gcc 11.3.1
                "libcxx_max_version": "3.4.29",
                "cxxabi_max_version": "1.3.13",
            },
        }
    ),
    "ubuntu-20.04-amd64": ExpectSuite(
        name="Ubuntu 20.04 (amd64)",
        manifest="fixtures/ubuntu-20.04-amd64.txt",
        tests={
            common_suites: {},
            libc_libcpp_suites: {
                "libc_max_version": "2.30",
                # gcc 9.3.0
                "libcxx_max_version": "3.4.28",
                "cxxabi_max_version": "1.3.12",
            },
        }
    ),
    "ubuntu-22.04-amd64": ExpectSuite(
        name="Ubuntu 22.04 (amd64)",
        manifest="fixtures/ubuntu-22.04-amd64.txt",
        tests={
            common_suites: {},
            libc_libcpp_suites: {
                "libc_max_version": "2.35",
                # gcc 11.2.0
                "libcxx_max_version": "3.4.29",
                "cxxabi_max_version": "1.3.13",
            },
        }
    ),
    "ubuntu-24.04-amd64": ExpectSuite(
        name="Ubuntu 24.04 (amd64)",
        manifest="fixtures/ubuntu-24.04-amd64.txt",
        tests={
            common_suites: {},
            libc_libcpp_suites: {
                "libc_max_version": "2.35",
                # gcc 11.2.0
                "libcxx_max_version": "3.4.29",
                "cxxabi_max_version": "1.3.13",
            },
        }
    ),
    "debian-11-amd64": ExpectSuite(
        name="Debian 11 (amd64)",
        manifest="fixtures/debian-11-amd64.txt",
        tests={
            common_suites: {},
            libc_libcpp_suites: {
                "libc_max_version": "2.31",
                # gcc 10.2.1
                "libcxx_max_version": "3.4.28",
                "cxxabi_max_version": "1.3.12",
            },
        }
    ),
    "debian-12-amd64": ExpectSuite(
        name="Debian 12 (amd64)",
        manifest="fixtures/debian-12-amd64.txt",
        tests={
            common_suites: {},
            libc_libcpp_suites: {
                "libc_max_version": "2.36",
                # gcc 12.1.0
                "libcxx_max_version": "3.4.30",
                "cxxabi_max_version": "1.3.13",
            },
        }
    ),
    "docker-image": ExpectSuite(
        name="Generic Docker Image",
        manifest=None,
        tests={
            docker_suites: {},
        }
    ),
    "docker-image-ubuntu-24.04": ExpectSuite(
        name="Ubuntu 24.04 Docker Image",
        manifest=None,
        tests={
            docker_suites: {
                "kong_uid": 1001,
                "kong_gid": 1001,
            },
        }
    ),
}

# populate arm64 and fips suites from amd64 suites

for target in list(targets.keys()):
    if target.split("-")[0] in ("alpine", "ubuntu", "debian", "amazonlinux", "el9"):
        e = deepcopy(targets[target])
        e.manifest = e.manifest.replace("-amd64.txt", "-arm64.txt")
        # Ubuntu 22.04 (arm64)
        e.name = e.name.replace("(amd64)", "(arm64)")
        e.tests[arm64_suites] = {}

        # TODO: cross compiled aws2023 uses rpath instead of runpath
        if target == "amazonlinux-2023-amd64":
            e.use_rpath = True

        # ubuntu-22.04-arm64
        targets[target.replace("-amd64", "-arm64")] = e
