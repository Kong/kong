load(":cc_toolchain_config.bzl", "cc_toolchain_config")

def _generate_wrappers_impl(ctx):
    wrapper_file = ctx.actions.declare_file("wrapper")
    ctx.actions.expand_template(
        template = ctx.file._wrapper_template,
        output = wrapper_file,
        substitutions = {
            "{{TOOLCHAIN_NAME}}": ctx.attr.toolchain_name,
        },
        is_executable = True,
    )

    dummy_output = ctx.actions.declare_file(ctx.attr.name + ".wrapper-marker")

    ctx.actions.run_shell(
        command = "build/toolchain/generate_wrappers.sh %s %s %s %s" % (
            ctx.attr.toolchain_name,
            wrapper_file.path,
            ctx.attr.tools_prefix,
            dummy_output.path,
        ),
        progress_message = "Create wrappers for " + ctx.attr.toolchain_name,
        inputs = [wrapper_file],
        outputs = [dummy_output],
    )

    return [DefaultInfo(files = depset([dummy_output, wrapper_file]))]

generate_wrappers = rule(
    implementation = _generate_wrappers_impl,
    attrs = {
        "toolchain_name": attr.string(mandatory = True),
        "tools_prefix": attr.string(mandatory = True),
        "_wrapper_template": attr.label(
            default = "//build/toolchain:templates/wrapper",
            allow_single_file = True,
        ),
    },
)

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
        toolchain_path_prefix = "wrappers-%s/" % identifier,  # is this required?
        tools_path_prefix = "wrappers-%s/%s" % (identifier, tools_prefix),
    )

    generate_wrappers(
        name = "%s_wrappers" % identifier,
        toolchain_name = identifier,
        tools_prefix = tools_prefix,
    )

    native.filegroup(
        name = "%s_files" % identifier,
        srcs = [
            ":%s_wrappers" % identifier,
            "@%s//:toolchain" % identifier,
        ],
    )

    native.cc_toolchain(
        name = "%s_cc_toolchain" % identifier,
        all_files = ":%s_files" % identifier,
        compiler_files = ":%s_files" % identifier,
        dwp_files = ":empty",
        linker_files = "%s_files" % identifier,
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
