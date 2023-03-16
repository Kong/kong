"""
Load this file for all Kong-specific build macros
and rules that you'd like to use in your BUILD files.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@kong_bindings//:variables.bzl", "KONG_VAR")

# A genrule variant that can output a directory.
def _kong_directory_genrule_impl(ctx):
    tree = ctx.actions.declare_directory(ctx.attr.output_dir)
    env = dicts.add(KONG_VAR, ctx.configuration.default_shell_env, {
        "GENRULE_OUTPUT_DIR": tree.path,
    })

    # XXX: remove the "env" from KONG_VAR which is a list
    env["OPENRESTY_PATCHES"] = ""

    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        tools = ctx.files.tools,
        outputs = [tree],
        command = "mkdir -p " + tree.path + " && " + ctx.expand_location(ctx.attr.cmd),
        env = env,
    )
    return [DefaultInfo(files = depset([tree]))]

kong_directory_genrule = rule(
    implementation = _kong_directory_genrule_impl,
    attrs = {
        "srcs": attr.label_list(),
        "cmd": attr.string(),
        "tools": attr.label_list(),
        "output_dir": attr.string(),
    },
)

# A rule that can be used as a meta rule that propagates multiple other rules
def _kong_rules_group_impl(ctx):
    return [DefaultInfo(files = depset(ctx.files.propagates))]

kong_rules_group = rule(
    implementation = _kong_rules_group_impl,
    attrs = {
        "propagates": attr.label_list(),
    },
)

def _kong_template_file_impl(ctx):
    ctx.actions.expand_template(
        template = ctx.file.template,
        output = ctx.outputs.output,
        substitutions = ctx.attr.substitutions,
        is_executable = ctx.attr.is_executable,
    )

    return [
        DefaultInfo(files = depset([ctx.outputs.output])),
    ]

kong_template_file = rule(
    implementation = _kong_template_file_impl,
    attrs = {
        "template": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "output": attr.output(
            mandatory = True,
        ),
        "substitutions": attr.string_dict(),
        "is_executable": attr.bool(default = False),
    },
)
