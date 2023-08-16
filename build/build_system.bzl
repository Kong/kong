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

_kong_template_attrs = {
    "template": attr.label(
        mandatory = True,
        allow_single_file = True,
    ),
    "output": attr.output(
        mandatory = True,
    ),
    "substitutions": attr.string_dict(),
    "srcs": attr.label_list(allow_files = True, doc = "List of locations to expand the template, in target configuration"),
    "tools": attr.label_list(allow_files = True, cfg = "exec", doc = "List of locations to expand the template, in exec configuration"),
    "is_executable": attr.bool(default = False),
    # hidden attributes
    "_cc_toolchain": attr.label(
        default = "@bazel_tools//tools/cpp:current_cc_toolchain",
    ),
}

def _render_template(ctx, output):
    substitutions = dict(ctx.attr.substitutions)
    for l in ctx.attr.srcs + ctx.attr.tools:
        files = l.files.to_list()
        if len(files) == 1:
            p = files[0].path
        else:
            p = "/".join(files[0].path.split("/")[:-1])  # get the directory
        substitutions["{{%s}}" % l.label] = p

    substitutions["{{CC}}"] = ctx.attr._cc_toolchain[cc_common.CcToolchainInfo].compiler_executable

    # yes, not a typo, use gcc for linker
    substitutions["{{LD}}"] = substitutions["{{CC}}"]

    ctx.actions.expand_template(
        template = ctx.file.template,
        output = output,
        substitutions = substitutions,
        is_executable = ctx.attr.is_executable,
    )

def _kong_template_file_impl(ctx):
    _render_template(ctx, ctx.outputs.output)

    return [
        DefaultInfo(files = depset([ctx.outputs.output])),
    ]

kong_template_file = rule(
    implementation = _kong_template_file_impl,
    attrs = _kong_template_attrs,
)

def _kong_template_genrule_impl(ctx):
    f = ctx.actions.declare_file(ctx.attr.name + ".rendered.sh")
    _render_template(ctx, f)

    ctx.actions.run_shell(
        outputs = [ctx.outputs.output],
        inputs = ctx.files.srcs + ctx.files.tools + [f],
        command = "{} {}".format(f.path, ctx.outputs.output.path),
        progress_message = ctx.attr.progress_message,
    )

    return [
        # don't list f as files/real output
        DefaultInfo(files = depset([ctx.outputs.output])),
    ]

kong_template_genrule = rule(
    implementation = _kong_template_genrule_impl,
    attrs = _kong_template_attrs | {
        "progress_message": attr.string(doc = "Message to display when running the command"),
    },
)

def _copyright_header(ctx):
    paths = ctx.execute(["find", ctx.path("."), "-type", "f"]).stdout.split("\n")

    copyright_content = ctx.read(ctx.path(Label("@kong//:distribution/COPYRIGHT-HEADER"))).replace("--", " ")
    copyright_content_js = "/*\n" + copyright_content + "*/\n\n"
    copyright_content_html = "<!--\n" + copyright_content + "-->\n\n"
    for path in paths:
        if path.endswith(".js") or path.endswith(".map") or path.endswith(".css"):
            content = ctx.read(path)
            if not content.startswith(copyright_content_js):
                # the default enabled |legacy_utf8| leads to a double-encoded utf-8
                # while writing utf-8 content read by |ctx.read|, let's disable it
                ctx.file(path, copyright_content_js + content, legacy_utf8 = False)

        elif path.endswith(".html"):
            content = ctx.read(path)
            if not content.startswith(copyright_content_html):
                # the default enabled |legacy_utf8| leads to a double-encoded utf-8
                # while writing utf-8 content read by |ctx.read|, let's disable it
                ctx.file(path, copyright_content_html + content, legacy_utf8 = False)

def _github_release_impl(ctx):
    ctx.file("WORKSPACE", "workspace(name = \"%s\")\n" % ctx.name)

    if ctx.attr.build_file:
        ctx.file("BUILD.bazel", ctx.read(ctx.attr.build_file))
    elif ctx.attr.build_file_content:
        ctx.file("BUILD.bazel", ctx.attr.build_file_content)

    os_name = ctx.os.name
    os_arch = ctx.os.arch

    if os_arch == "aarch64":
        os_arch = "arm64"
    elif os_arch == "x86_64":
        os_arch = "amd64"
    elif os_arch != "amd64":
        fail("Unsupported arch %s" % os_arch)

    if os_name == "mac os x":
        os_name = "macOS"
    elif os_name != "linux":
        fail("Unsupported OS %s" % os_name)

    gh_bin = "%s" % ctx.path(Label("@gh_%s_%s//:bin/gh" % (os_name, os_arch)))
    args = [gh_bin, "release", "download", ctx.attr.tag, "-R", ctx.attr.repo]
    downloaded_file = None
    if ctx.attr.pattern:
        if "/" in ctx.attr.pattern or ".." in ctx.attr.pattern:
            fail("/ and .. are not allowed in pattern")
        downloaded_file = ctx.attr.pattern.replace("*", "_")
        args += ["-p", ctx.attr.pattern]
    elif ctx.attr.archive:
        args.append("--archive=" + ctx.attr.archive)
        downloaded_file = "gh-release." + ctx.attr.archive.split(".")[-1]
    else:
        fail("at least one of pattern or archive must be set")

    args += ["-O", downloaded_file]

    ret = ctx.execute(args)

    if ret.return_code != 0:
        gh_token_set = "GITHUB_TOKEN is set, is it valid?"
        if not ctx.os.environ.get("GITHUB_TOKEN", ""):
            gh_token_set = "GITHUB_TOKEN is not set, is this a private repo?"
        fail("Failed to download release (%s): %s, exit: %d" % (gh_token_set, ret.stderr, ret.return_code))

    ctx.extract(downloaded_file, stripPrefix = ctx.attr.strip_prefix)

    if not ctx.attr.skip_add_copyright_header:
        _copyright_header(ctx)

github_release = repository_rule(
    implementation = _github_release_impl,
    attrs = {
        "tag": attr.string(mandatory = True),
        "pattern": attr.string(mandatory = False),
        "archive": attr.string(mandatory = False, values = ["zip", "tar.gz"]),
        "strip_prefix": attr.string(default = "", doc = "Strip prefix from downloaded files"),
        "repo": attr.string(mandatory = True),
        "build_file": attr.label(allow_single_file = True),
        "build_file_content": attr.string(),
        "skip_add_copyright_header": attr.bool(default = False, doc = "Whether to inject COPYRIGHT-HEADER into downloaded files, only required for webuis"),
    },
)
