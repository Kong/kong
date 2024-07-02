load(":cc_toolchain_config.bzl", "cc_toolchain_config")
load(":managed_toolchain.bzl", "aarch64_glibc_distros", "define_managed_toolchain")

package(default_visibility = ["//visibility:public"])

filegroup(name = "empty")

###################
# aarch64-linux-gnu (installed with system)

toolchain(
    name = "local_aarch64-linux-gnu_toolchain",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
        "//build/platforms/distro:generic",
    ],
    toolchain = ":local_aarch64-linux-gnu_cc_toolchain",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

cc_toolchain_config(
    name = "local_aarch64-linux-gnu_cc_toolchain_config",
    compiler_configuration = {},
    target_cpu = "aarch64",
    toolchain_path_prefix = "/usr/aarch64-linux-gnu/",  # is this required?
    tools_prefix = "aarch64-linux-gnu-",
)

cc_toolchain(
    name = "local_aarch64-linux-gnu_cc_toolchain",
    all_files = ":empty",
    compiler_files = ":empty",
    dwp_files = ":empty",
    linker_files = ":empty",
    objcopy_files = ":empty",
    strip_files = ":empty",
    supports_param_files = 0,
    toolchain_config = ":local_aarch64-linux-gnu_cc_toolchain_config",
    toolchain_identifier = "local_aarch64-linux-gnu_cc_toolchain",
)

###################
# managed toolchains (downloaded by Bazel)

define_managed_toolchain(
    arch = "x86_64",
    gcc_version = aarch64_glibc_distros["aws2"],
    libc = "gnu",
    target_compatible_with = ["//build/platforms/distro:aws2"],
    vendor = "aws2",
)

[
    define_managed_toolchain(
        arch = "aarch64",
        gcc_version = aarch64_glibc_distros[vendor],
        libc = "gnu",
        target_compatible_with = ["//build/platforms/distro:" + vendor],
        vendor = vendor,
    )
    for vendor in aarch64_glibc_distros
]
