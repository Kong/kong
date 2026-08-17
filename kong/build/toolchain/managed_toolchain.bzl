load(":cc_toolchain_config.bzl", "cc_toolchain_config")

aarch64_glibc_distros = {
    "rhel9": "11",
    "rhel8": "8",
    "aws2023": "11",
    "aws2": "8",
}

def define_managed_toolchain(
        name = None,
        arch = "x86_64",
        vendor = "unknown",
        libc = "gnu",
        gcc_version = "11",
        ld = "gcc",
        target_compatible_with = []):
    identifier = "{arch}-{vendor}-linux-{libc}-gcc-{gcc_version}".format(
        arch = arch,
        vendor = vendor,
        libc = libc,
        gcc_version = gcc_version,
    )

    tools_prefix = "{arch}-{vendor}-linux-{libc}-".format(
        arch = arch,
        vendor = vendor,
        libc = libc,
    )

    native.toolchain(
        name = "%s_toolchain" % identifier,
        exec_compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
        target_compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:%s" % arch,
        ] + target_compatible_with,
        toolchain = ":%s_cc_toolchain" % identifier,
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )

    cc_toolchain_config(
        name = "%s_cc_toolchain_config" % identifier,
        ld = ld,
        target_cpu = arch,
        target_libc = libc,
        tools_prefix = tools_prefix,
        src = "@%s//:toolchain" % identifier,
    )

    native.cc_toolchain(
        name = "%s_cc_toolchain" % identifier,
        all_files = "@%s//:toolchain" % identifier,
        compiler_files = "@%s//:toolchain" % identifier,
        dwp_files = ":empty",
        linker_files = "@%s//:toolchain" % identifier,
        objcopy_files = ":empty",
        strip_files = ":empty",
        supports_param_files = 0,
        toolchain_config = ":%s_cc_toolchain_config" % identifier,
        toolchain_identifier = "%s_cc_toolchain" % identifier,
    )

def register_managed_toolchain(name = None, arch = "x86_64", vendor = "unknown", libc = "gnu", gcc_version = "11"):
    identifier = "{arch}-{vendor}-linux-{libc}-gcc-{gcc_version}".format(
        arch = arch,
        vendor = vendor,
        libc = libc,
        gcc_version = gcc_version,
    )
    native.register_toolchains("//build/toolchain:%s_toolchain" % identifier)

def register_all_toolchains(name = None):
    native.register_toolchains("//build/toolchain:local_aarch64-linux-gnu_toolchain")

    register_managed_toolchain(
        arch = "x86_64",
        gcc_version = "8",
        libc = "gnu",
        vendor = "aws2",
    )

    for vendor in aarch64_glibc_distros:
        register_managed_toolchain(
            arch = "aarch64",
            gcc_version = aarch64_glibc_distros[vendor],
            libc = "gnu",
            vendor = vendor,
        )
