#!/usr/bin/env python3

import os
import sys
import glob
import atexit
import difflib
import argparse
import tempfile
from io import StringIO
from typing import List
from pathlib import Path

import config

from explain import ExplainOpts, FileInfo, ElfFileInfo, NginxInfo
from expect import ExpectChain, glob_match_ignore_slash


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--path", "-p", help="Path to the directory to compare", required=True)
    parser.add_argument(
        "--output", "-o", help="Path to output manifest, use - to write to stdout")
    parser.add_argument(
        "--suite", "-s", help="Expect suite name to test, defined in config.py")
    parser.add_argument(
        "--file_list", "-f", help="Path to the files list to explain for manifest; " +
        "each line in the file should be a glob pattern of full path")
    parser.add_argument(
        "--owners", help="Display owner and group", action="store_true")
    parser.add_argument(
        "--mode", help="Display mode", action="store_true")
    parser.add_argument(
        "--size", help="Display size", action="store_true")
    parser.add_argument("--arch",
                        help="Display ELF architecture", action="store_true")
    parser.add_argument("--merge_rpaths_runpaths",
                        help="Treate RPATH and RUNPATH as same", action="store_true")
    parser.add_argument(
        "--imported_symbols", help="Display imported symbols", action="store_true")
    parser.add_argument(
        "--exported_symbols", help="Display exported symbols", action="store_true")
    parser.add_argument("--version_requirement",
                        help="Display exported symbols",
                        action="store_true")

    return parser.parse_args()


def read_glob(path: str):
    if not path:
        return ["**"]

    with open(path, "r") as f:
        return f.read().splitlines()


def gather_files(path: str):
    ext = os.path.splitext(path)[1]
    if ext in (".deb", ".rpm") or path.endswith(".apk.tar.gz"):
        t = tempfile.TemporaryDirectory()
        atexit.register(t.cleanup)

        if ext == ".deb":
            code = os.system(
                "ar p %s data.tar.gz | tar -C %s -xz" % (path, t.name))
        elif ext == ".rpm":
            # GNU cpio and rpm2cpio is needed
            code = os.system(
                "rpm2cpio %s | cpio --no-preserve-owner --no-absolute-filenames -idm -D %s" % (path, t.name))
        elif ext == ".gz":
            code = os.system("tar -C %s -xf %s" % (t.name, path))

        if code != 0:
            raise Exception("Failed to extract %s" % path)

        return t.name
    elif not Path(path).is_dir():
        raise Exception("Don't know how to process \"%s\"" % path)

    return path


def walk_files(path: str):
    results = []
    for file in sorted(glob.glob("**", root_dir=path, recursive=True)):
        full_path = os.path.join(path, file)

        if not file.startswith("/") and not file.startswith("./"):
            file = '/' + file  # prettifier

        if os.path.basename(file) == "nginx":
            f = NginxInfo(full_path, file)
        elif os.path.splitext(file)[1] == ".so" or os.path.basename(os.path.dirname(file)) in ("bin", "lib", "lib64", "sbin"):
            p = Path(full_path)
            if p.is_symlink():
                continue
            f = ElfFileInfo(full_path, file)
        else:
            f = FileInfo(full_path, file)

        config.transform(f)
        results.append(f)

    return results


def write_manifest(title: str, results: List[FileInfo], globs: List[str], opts: ExplainOpts):
    f = StringIO()

    for result in results:
        if not glob_match_ignore_slash(result.relpath, globs):
            continue

        entries = result.explain(opts)
        ident = 2
        first = True
        for k, v in entries:
            if isinstance(v, list):
                v = ("\n" + " " * ident + "- ").join([""] + v)
            else:
                v = " %s" % v
            if first:
                f.write("-" + (" " * (ident-1)))
                first = False
            else:
                f.write(" " * ident)
            f.write("%-10s:%s\n" % (k, v))
        f.write("\n")

    f.flush()

    return f.getvalue().encode("utf-8")


if __name__ == "__main__":
    args = parse_args()

    if not args.suite and not args.output:
        raise Exception("At least one of --suite or --output is required")

    if args.suite and Path(args.path).is_dir():
        raise Exception(
            "suite mode only works with archive files (deb, rpm, apk.tar.gz, etc.")

    directory = gather_files(args.path)

    infos = walk_files(directory)

    if Path(args.path).is_file():
        title = "contents in archive %s" % args.path
    else:
        title = "contents in directory %s" % args.path

    globs = read_glob(args.file_list)

    manifest = write_manifest(title, infos, globs, ExplainOpts.from_args(args))

    if args.suite:
        if args.suite not in config.targets:
            closest = difflib.get_close_matches(
                config.targets.keys(), args.suite, 1)
            maybe = ""
            if closest:
                maybe = ", maybe you meant %s" % closest[0]
            raise Exception("Unknown suite %s%s" % (args.suite, maybe))
        E = ExpectChain(infos)
        E.compare_manifest(config.targets[args.suite], manifest)
        E.run(config.targets[args.suite])

    if args.output:
        if args.output == "-":
            f = sys.stdout
            manifest = manifest.decode("utf-8")
        else:
            f = open(args.output, "wb")
        f.write(manifest)
        if args.output != "-":
            f.close()
