#!/usr/bin/env python3

import os
import sys
import glob
import time
import atexit
import difflib
import pathlib
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
        "--path", "-p", help="Path to the directory, binary package or docker image tag to compare")
    parser.add_argument(
        "--image", help="Docker image tag to compare")
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

def gather_files(path: str, image: str):
    if image:
        t = tempfile.TemporaryDirectory()
        atexit.register(t.cleanup)

        code = os.system("docker pull {img} && docker create --name={name} {img} && docker export {name} | tar xf - -C {tmp} && docker rm -f {name}".format(
            img=image, 
            name="explain_manifest_%d" % time.time(), 
            tmp=t.name
        ))

        if code != 0:
            raise Exception("Failed to extract image %s" % image)
        return t.name
    
    ext = os.path.splitext(path)[1]
    if ext in (".deb", ".rpm") or path.endswith(".apk.tar.gz"):
        t = tempfile.TemporaryDirectory()
        atexit.register(t.cleanup)

        if ext == ".deb":
            code = os.system(
                "ar p %s data.tar.gz | tar -C %s -xz" % (path, t.name))
        elif ext == ".rpm":
            # rpm2cpio is needed
            # rpm2archive ships with rpm2cpio on debians
            code = os.system(
                """
                    rpm2archive %s && tar -C %s -xf %s.tgz
                """ % (path, t.name, path))
        elif ext == ".gz":
            code = os.system("tar -C %s -xf %s" % (t.name, path))

        if code != 0:
            raise Exception("Failed to extract %s" % path)

        return t.name
    elif not Path(path).is_dir():
        raise Exception("Don't know how to process \"%s\"" % path)

    return path


def walk_files(path: str, globs: List[str]):
    results = []
    # use pathlib instead of glob.glob to avoid recurse into symlink dir
    for file in sorted(pathlib.Path(path).rglob("*")):
        full_path = str(file)
        file = str(file.relative_to(path))

        if globs and not glob_match_ignore_slash(file, globs):
            continue

        if not file.startswith("/") and not file.startswith("./"):
            file = '/' + file  # prettifier

        if file.endswith("sbin/nginx"):
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

    if not args.path and not args.image:
        raise Exception("At least one of --path or --image is required")

    if args.image and os.getuid() != 0:
        raise Exception("Running as root is required to explain an image")

    if args.path and Path(args.path).is_dir():
        raise Exception(
            "suite mode only works with archive files (deb, rpm, apk.tar.gz, etc.")

    directory = gather_files(args.path, args.image)

    globs = read_glob(args.file_list)

    # filter by filelist only when explaining an image to reduce time
    infos = walk_files(directory, globs=globs if args.image else None)

    if args.image:
        title = "contents in image %s" % args.image
    elif Path(args.path).is_file():
        title = "contents in archive %s" % args.path
    else:
        title = "contents in directory %s" % args.path

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
