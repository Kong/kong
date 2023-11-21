load(":cc_toolchain_config.bzl", "cc_toolchain_config")

package(default_visibility = ["//visibility:public"])

filegroup(name = "empty")

###################
# aarch64-linux-gnu (installed with system)

toolchain(
    name = "gcc_cross_arm64_toolchain",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:arm64",
    ],
    toolchain = ":gcc_cross_arm64_cc_toolchain",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

cc_toolchain_config(
    name = "gcc_cross_arm64_cc_toolchain_config",
    compiler_configuration = {},
    target_cpu = "aarch64",
    toolchain_path_prefix = "/usr/aarch64-linux-gnu/",  # is this required?
    tools_path_prefix = "/usr/bin/aarch64-linux-gnu-",
)

cc_toolchain(
    name = "gcc_cross_arm64_cc_toolchain",
    all_files = ":empty",
    compiler_files = ":empty",
    dwp_files = ":empty",
    linker_files = ":empty",
    objcopy_files = ":empty",
    strip_files = ":empty",
    supports_param_files = 0,
    toolchain_config = ":gcc_cross_arm64_cc_toolchain_config",
    toolchain_identifier = "gcc_cross_arm64-toolchain",
)

###################
# x86_64-linux-musl (downloaded by bazel)

toolchain(
    name = "gcc_cross_musl_x86_64_toolchain",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
        "//:musl",
    ],
    toolchain = ":gcc_cross_musl_x86_64_cc_toolchain",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

cc_toolchain_config(
    name = "gcc_cross_musl_x86_64_cc_toolchain_config",
    ld = "gcc",
    target_cpu = "x86_64",
    target_libc = "musl",
    toolchain_path_prefix = "gcc-11-x86_64-linux-musl-wrappers/",  # is this required?
    tools_path_prefix = "gcc-11-x86_64-linux-musl-wrappers/x86_64-linux-musl-",
)

filegroup(
    name = "wrappers",
    srcs = glob([
        "gcc-11-x86_64-linux-musl-wrappers/**",
    ]),
)

filegroup(
    name = "musl_toolchain_files",
    srcs = [
        ":wrappers",
        "@gcc-11-x86_64-linux-musl-cross//:toolchain",
    ],
)

cc_toolchain(
    name = "gcc_cross_musl_x86_64_cc_toolchain",
    all_files = ":musl_toolchain_files",
    compiler_files = ":musl_toolchain_files",
    dwp_files = ":empty",
    linker_files = ":musl_toolchain_files",
    objcopy_files = ":empty",
    strip_files = ":empty",
    supports_param_files = 0,
    toolchain_config = ":gcc_cross_musl_x86_64_cc_toolchain_config",
    toolchain_identifier = "gcc_cross_musl_x86_64-toolchain",
)
