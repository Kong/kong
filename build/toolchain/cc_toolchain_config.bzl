# Copyright 2021 The Bazel Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "feature", "flag_group", "flag_set", "tool_path", "with_feature_set")
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load("@toolchain_bindings//:variables.bzl", "INTERNAL_ROOT")

all_compile_actions = [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.assemble,
    ACTION_NAMES.preprocess_assemble,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.clif_match,
    ACTION_NAMES.lto_backend,
]

all_cpp_compile_actions = [
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.clif_match,
]

all_link_actions = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

lto_index_actions = [
    ACTION_NAMES.lto_index_for_executable,
    ACTION_NAMES.lto_index_for_dynamic_library,
    ACTION_NAMES.lto_index_for_nodeps_dynamic_library,
]

# Bazel 4.* doesn't support nested starlark functions, so we cannot simplify
#_fmt_flags() by defining it as a nested function.
def _fmt_flags(flags, toolchain_path_prefix):
    return [f.format(toolchain_path_prefix = toolchain_path_prefix) for f in flags]

# Macro for calling cc_toolchain_config from @bazel_tools with setting the
# right paths and flags for the tools.
def _cc_toolchain_config_impl(ctx):
    target_cpu = ctx.attr.target_cpu
    toolchain_path_prefix = ctx.attr.toolchain_path_prefix
    tools_prefix = ctx.attr.tools_prefix
    compiler_configuration = ctx.attr.compiler_configuration

    # update to absolute paths if we are using a managed toolchain (downloaded by bazel)
    if len(ctx.files.src) > 0:
        if toolchain_path_prefix:
            fail("Both `src` and `toolchain_path_prefix` is set, but toolchain_path_prefix will be overrided if `src` is set.")

        # file is something like external/aarch64-rhel9-linux-gnu-gcc-11/aarch64-rhel9-linux-gnu/bin/ar
        # we will take aarch64-rhel9-linux-gnu-gcc-11/aarch64-rhel9-linux-gnu
        ar_path = None
        for f in ctx.files.src:
            if f.path.endswith("bin/ar"):
                ar_path = f.path
                break
        if not ar_path:
            fail("Cannot find ar in the toolchain")
        toolchain_path_prefix = INTERNAL_ROOT + "/" + "/".join(ar_path.split("/")[1:3])

        _tools_root_dir = INTERNAL_ROOT + "/" + ctx.files.src[0].path.split("/")[1]
        tools_prefix = _tools_root_dir + "/bin/" + tools_prefix
    else:
        tools_prefix = "/usr/bin/" + tools_prefix

    # Unfiltered compiler flags; these are placed at the end of the command
    # line, so take precendence over any user supplied flags through --copts or
    # such.
    unfiltered_compile_flags = [
        # Do not resolve our symlinked resource prefixes to real paths.
        "-no-canonical-prefixes",
        # Reproducibility
        "-Wno-builtin-macro-redefined",
        "-D__DATE__=\"redacted\"",
        "-D__TIMESTAMP__=\"redacted\"",
        "-D__TIME__=\"redacted\"",
        "-fdebug-prefix-map={}=__bazel_toolchain__/".format(toolchain_path_prefix),
    ]

    # Default compiler flags:
    compile_flags = [
        # "--target=" + target_system_name,
        # Security
        "-U_FORTIFY_SOURCE",  # https://github.com/google/sanitizers/issues/247
        "-fstack-protector",
        "-fno-omit-frame-pointer",
        # Diagnostics
        "-Wall",
    ]

    dbg_compile_flags = ["-g", "-fstandalone-debug"]

    opt_compile_flags = [
        "-g0",
        "-O2",
        "-D_FORTIFY_SOURCE=1",
        "-DNDEBUG",
        "-ffunction-sections",
        "-fdata-sections",
    ]

    link_flags = [
        # "--target=" + target_system_name,
        "-lm",
        "-lstdc++",
        "-no-canonical-prefixes",
    ]

    # Similar to link_flags, but placed later in the command line such that
    # unused symbols are not stripped.
    link_libs = []

    # Note that for xcompiling from darwin to linux, the native ld64 is
    # not an option because it is not a cross-linker, so lld is the
    # only option.

    link_flags.extend([
        "-Wl,--build-id=md5",
        "-Wl,--hash-style=gnu",
        "-Wl,-z,relro,-z,now",
    ])

    opt_link_flags = ["-Wl,--gc-sections"]

    # Coverage flags:
    coverage_compile_flags = ["-fprofile-instr-generate", "-fcoverage-mapping"]
    coverage_link_flags = ["-fprofile-instr-generate"]

    ## NOTE: framework paths is missing here; unix_cc_toolchain_config
    ## doesn't seem to have a feature for this.

    # C++ built-in include directories:
    cxx_builtin_include_directories = [
        "/usr/" + target_cpu + "-linux-gnu/include",
        # let's just add any version we might need in here (debian based)
        "/usr/lib/gcc-cross/" + target_cpu + "-linux-gnu/13/include",
        "/usr/lib/gcc-cross/" + target_cpu + "-linux-gnu/12/include",
        "/usr/lib/gcc-cross/" + target_cpu + "-linux-gnu/11/include",
        "/usr/lib/gcc-cross/" + target_cpu + "-linux-gnu/10/include",
    ]

    if len(ctx.files.src) > 0:
        # define absolute path for managed toolchain
        # bazel doesn't support relative path for cxx_builtin_include_directories
        cxx_builtin_include_directories.append(toolchain_path_prefix + "/include")
        cxx_builtin_include_directories.append(toolchain_path_prefix + "/sysroot/usr/include")
        cxx_builtin_include_directories.append(_tools_root_dir + "/lib/gcc")

    # sysroot_path = compiler_configuration["sysroot_path"]
    # sysroot_prefix = ""
    # if sysroot_path:
    #     sysroot_prefix = "%sysroot%"

    # cxx_builtin_include_directories.extend([
    #     sysroot_prefix + "/include",
    #     sysroot_prefix + "/usr/include",
    #     sysroot_prefix + "/usr/local/include",
    # ])

    if "additional_include_dirs" in compiler_configuration:
        cxx_builtin_include_directories.extend(compiler_configuration["additional_include_dirs"])

    ## NOTE: make variables are missing here; unix_cc_toolchain_config doesn't
    ## pass these to `create_cc_toolchain_config_info`.

    # The tool names come from [here](https://github.com/bazelbuild/bazel/blob/c7e58e6ce0a78fdaff2d716b4864a5ace8917626/src/main/java/com/google/devtools/build/lib/rules/cpp/CppConfiguration.java#L76-L90):
    # NOTE: Ensure these are listed in toolchain_tools in toolchain/internal/common.bzl.
    tool_paths = [
        tool_path(
            name = "ar",
            path = tools_prefix + "ar",
        ),
        tool_path(
            name = "cpp",
            path = tools_prefix + "g++",
        ),
        tool_path(
            name = "gcc",
            path = tools_prefix + "gcc",
        ),
        tool_path(
            name = "gcov",
            path = tools_prefix + "gcov",
        ),
        tool_path(
            name = "ld",
            path = tools_prefix + ctx.attr.ld,
        ),
        tool_path(
            name = "nm",
            path = tools_prefix + "nm",
        ),
        tool_path(
            name = "objcopy",
            path = tools_prefix + "objcopy",
        ),
        tool_path(
            name = "objdump",
            path = tools_prefix + "objdump",
        ),
        tool_path(
            name = "strip",
            path = tools_prefix + "strip",
        ),
    ]

    cxx_flags = []

    # Replace flags with any user-provided overrides.
    if "compile_flags" in compiler_configuration:
        compile_flags = compile_flags + _fmt_flags(compiler_configuration["compile_flags"], toolchain_path_prefix)
    if "cxx_flags" in compiler_configuration:
        cxx_flags = cxx_flags + _fmt_flags(compiler_configuration["cxx_flags"], toolchain_path_prefix)
    if "link_flags" in compiler_configuration:
        link_flags = link_flags + _fmt_flags(compiler_configuration["link_flags"], toolchain_path_prefix)
    if "link_libs" in compiler_configuration:
        link_libs = link_libs + _fmt_flags(compiler_configuration["link_libs"], toolchain_path_prefix)
    if "opt_compile_flags" in compiler_configuration:
        opt_compile_flags = opt_compile_flags + _fmt_flags(compiler_configuration["opt_compile_flags"], toolchain_path_prefix)
    if "opt_link_flags" in compiler_configuration:
        opt_link_flags = opt_link_flags + _fmt_flags(compiler_configuration["opt_link_flags"], toolchain_path_prefix)
    if "dbg_compile_flags" in compiler_configuration:
        dbg_compile_flags = dbg_compile_flags + _fmt_flags(compiler_configuration["dbg_compile_flags"], toolchain_path_prefix)
    if "coverage_compile_flags" in compiler_configuration:
        coverage_compile_flags = coverage_compile_flags + _fmt_flags(compiler_configuration["coverage_compile_flags"], toolchain_path_prefix)
    if "coverage_link_flags" in compiler_configuration:
        coverage_link_flags = coverage_link_flags + _fmt_flags(compiler_configuration["coverage_link_flags"], toolchain_path_prefix)
    if "unfiltered_compile_flags" in compiler_configuration:
        unfiltered_compile_flags = unfiltered_compile_flags + _fmt_flags(compiler_configuration["unfiltered_compile_flags"], toolchain_path_prefix)

    default_compile_flags_feature = feature(
        name = "default_compile_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = all_compile_actions,
                flag_groups = ([
                    flag_group(
                        flags = compile_flags,
                    ),
                ] if compile_flags else []),
            ),
            flag_set(
                actions = all_compile_actions,
                flag_groups = ([
                    flag_group(
                        flags = dbg_compile_flags,
                    ),
                ] if dbg_compile_flags else []),
                with_features = [with_feature_set(features = ["dbg"])],
            ),
            flag_set(
                actions = all_compile_actions,
                flag_groups = ([
                    flag_group(
                        flags = opt_compile_flags,
                    ),
                ] if opt_compile_flags else []),
                with_features = [with_feature_set(features = ["opt"])],
            ),
            flag_set(
                actions = all_cpp_compile_actions + [ACTION_NAMES.lto_backend],
                flag_groups = ([
                    flag_group(
                        flags = cxx_flags,
                    ),
                ] if cxx_flags else []),
            ),
        ],
    )

    default_link_flags_feature = feature(
        name = "default_link_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = all_link_actions + lto_index_actions,
                flag_groups = ([
                    flag_group(
                        flags = link_flags,
                    ),
                ] if link_flags else []),
            ),
            flag_set(
                actions = all_link_actions + lto_index_actions,
                flag_groups = ([
                    flag_group(
                        flags = opt_link_flags,
                    ),
                ] if opt_link_flags else []),
                with_features = [with_feature_set(features = ["opt"])],
            ),
        ],
    )

    unfiltered_compile_flags_feature = feature(
        name = "unfiltered_compile_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = all_compile_actions,
                flag_groups = ([
                    flag_group(
                        flags = unfiltered_compile_flags,
                    ),
                ] if unfiltered_compile_flags else []),
            ),
        ],
    )

    supports_pic_feature = feature(name = "supports_pic", enabled = True)
    supports_dynamic_linker_feature = feature(name = "supports_dynamic_linker", enabled = True)
    dbg_feature = feature(name = "dbg")
    opt_feature = feature(name = "opt")
    features = [
        supports_dynamic_linker_feature,
        supports_pic_feature,
        dbg_feature,
        opt_feature,
        default_compile_flags_feature,
        unfiltered_compile_flags_feature,
        default_link_flags_feature,
    ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        compiler = "gcc",
        features = features,
        toolchain_identifier = target_cpu + "-linux-gnu",
        host_system_name = "local",
        target_cpu = target_cpu,
        target_system_name = target_cpu + "-linux-gnu",
        target_libc = ctx.attr.target_libc,
        # abi_version = "unknown",
        # abi_libc_version = "unknown",
        cxx_builtin_include_directories = cxx_builtin_include_directories,
        tool_paths = tool_paths,
    )

cc_toolchain_config = rule(
    implementation = _cc_toolchain_config_impl,
    attrs = {
        "target_cpu": attr.string(),
        "toolchain_path_prefix": attr.string(doc = "The root directory of the toolchain."),
        "tools_prefix": attr.string(doc = "The tools prefix, for example aarch64-linux-gnu-"),
        "compiler_configuration": attr.string_list_dict(allow_empty = True, default = {}),
        "target_libc": attr.string(default = "gnu"),
        "ld": attr.string(default = "gcc"),
        "src": attr.label(doc = "Reference to the managed toolchain repository, if set, toolchain_path_prefix will not be used and tools_prefix will be infered "),
    },
    provides = [CcToolchainConfigInfo],
)
