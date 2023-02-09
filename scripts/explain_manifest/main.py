#!/usr/bin/env python3

import os
import re
import sys
import glob
import atexit
import argparse
import tempfile
from pathlib import Path

import lief
from globmatch import glob_match

import config


class ExplainOpts():
    # General
    owners = True
    mode = True
    size = False
    # ELF
    merge_rpaths_runpaths = False
    imported_symbols = False
    exported_symbols = False
    version_requirement = True

    @classmethod
    def from_args(this, args):
        this.owners = args.owners
        this.mode = args.mode
        this.size = args.size
        this.merge_rpaths_runpaths = args.merge_rpaths_runpaths
        this.imported_symbols = args.imported_symbols
        this.exported_symbols = args.exported_symbols
        this.version_requirement = args.version_requirement

        return this


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--path", "-p", help="Path to the directory to compare", required=True)
    parser.add_argument(
        "--output", "-o", help="Path to output manifest, use - to write to stdout", default="-")
    parser.add_argument(
        "--file_list", "-f", help="Path to the files list to explain for manifest; " + \
                                    "each line in the file should be a glob pattern of full path")
    parser.add_argument(
        "--owners", help="Export and compare owner and group", action="store_true")
    parser.add_argument(
        "--mode", help="Export and compare mode", action="store_true")
    parser.add_argument(
        "--size", help="Export and compare size", action="store_true")
    parser.add_argument("--merge_rpaths_runpaths",
                        help="Treate RPATH and RUNPATH as same", action="store_true")
    parser.add_argument(
        "--imported_symbols", help="Export and compare imported symbols", action="store_true")
    parser.add_argument(
        "--exported_symbols", help="Export and compare exported symbols", action="store_true")
    parser.add_argument("--version_requirement",
                        help="Export and compare exported symbols (default to True)",
                        action="store_true", default=True)

    return parser.parse_args()


def read_glob(path):
    if not path:
        return ["**"]

    with open(path, "r") as f:
        return f.read().splitlines()


def gather_files(path):
    ext = os.path.splitext(path)[1]
    if ext in (".deb", ".rpm") or path.endswith(".apk.tar.gz"):
        t = tempfile.TemporaryDirectory()
        atexit.register(t.cleanup)

        if ext == ".deb":
            code = os.system(
                "ar p %s data.tar.gz | tar -C %s -xz" % (path, t.name))
        elif ext == ".rpm":
            # GNU gpio and rpm2cpio is needed
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


class FileInfo():
    def __init__(self, path, relpath):
        self.path = path
        self.relpath = relpath
        self.mode = os.stat(path).st_mode
        self.uid = os.stat(path).st_uid
        self.gid = os.stat(path).st_gid
        self.size = os.stat(path).st_size

        if Path(path).is_symlink():
            self.link = os.readlink(path)
        elif Path(path).is_dir():
            self.directory = True

    def explain(self, opts):
        lines = [("Path", self.relpath)]
        if hasattr(self, "link"):
            lines.append(("Link", self.link))
            lines.append(("Type", "link"))
        elif hasattr(self, "directory"):
            lines.append(("Type", "directory"))

        if opts.owners:
            lines.append(("Uid,Gid",  "%s, %s" % (self.uid, self.gid)))
        if opts.mode:
            lines.append(("Mode", oct(self.mode)))
        if opts.size:
            lines.append(("Size", self.size))

        return lines


class ElfFileInfo(FileInfo):
    def __init__(self, path, relpath):
        super().__init__(path, relpath)

        self.needed = []
        self.rpath = None
        self.runpath = None
        self.get_exported_symbols = None
        self.get_imported_symbols = None
        self.version_requirement = []

        binary = lief.parse(path)
        if not binary:  # not an ELF file, malformed, etc
            return

        for d in binary.dynamic_entries:
            if d.tag == lief.ELF.DYNAMIC_TAGS.NEEDED:
                self.needed.append(d.name)
            elif d.tag == lief.ELF.DYNAMIC_TAGS.RPATH:
                self.rpath = d.name
            elif d.tag == lief.ELF.DYNAMIC_TAGS.RUNPATH:
                self.runpath = d.name

        # create closures and lazily evaluated
        self.get_exported_symbols = lambda: sorted(
            [d.name for d in binary.exported_symbols])
        self.get_imported_symbols = lambda: sorted(
            [d.name for d in binary.imported_symbols])

        for f in binary.symbols_version_requirement:
            self.version_requirement.append("%s (%s)" % (
                f.name, ", ".join(sorted([a.name for a in f.get_auxiliary_symbols()]))))
        self.version_requirement = sorted(self.version_requirement)

    def explain(self, opts):
        pline = super().explain(opts)

        lines = []

        if self.needed:
            lines.append(("Needed", self.needed))
        if self.rpath:
            lines.append(("Rpath", self.rpath))
        if self.runpath:
            lines.append(("Runpath", self.runpath))
        if opts.exported_symbols and self.get_exported_symbols:
            lines.append(("Exported", self.get_exported_symbols()))
        if opts.imported_symbols and self.get_imported_symbols:
            lines.append(("Imported", self.get_imported_symbols()))
        if opts.version_requirement and self.version_requirement:
            lines.append(("Version Requirement", self.version_requirement))

        return pline + lines


class NginxInfo(ElfFileInfo):
    def __init__(self, path, relpath):
        super().__init__(path, relpath)

        self.modules = []
        self.linked_openssl = None

        binary = lief.parse(path)

        for s in binary.strings:
            if re.match("\s*--prefix=/", s):
                for m in re.findall("add(?:-dynamic)?-module=(.*?) ", s):
                    if m.startswith("../"):  # skip bundled modules
                        continue
                    pdir = os.path.basename(os.path.dirname(m))
                    mname = os.path.basename(m)
                    if pdir in ("external", "distribution"):
                        self.modules.append(mname)
                    else:
                        self.modules.append(os.path.join(pdir, mname))
                self.modules = sorted(self.modules)
            elif m := re.match("^built with (.+) \(running with", s):
                self.linked_openssl = m.group(1).strip()

    def explain(self, opts):
        pline = super().explain(opts)

        lines = []
        lines.append(("Modules", self.modules))
        lines.append(("OpenSSL", self.linked_openssl))

        return pline + lines


def walk_files(path, globs):
    results = []
    for file in sorted(glob.glob("**", root_dir=path, recursive=True)):
        if not glob_match(file, globs):
            continue

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


def write_manifest(title, results, opts: ExplainOpts, output):
    if output == "-":
        f = sys.stdout
    else:
        f = open(output, "w")

    print("# Manifest for %s\n\n" % title)

    for result in results:
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

    if f != sys.stdout:
        f.close()


if __name__ == "__main__":
    args = parse_args()

    globs = read_glob(args.file_list)

    directory = gather_files(args.path)

    infos = walk_files(directory, globs)

    if Path(args.path).is_file():
        title = "contents in archive %s" % args.path
    else:
        title = "contents in directory %s" % args.path

    write_manifest(title, infos, ExplainOpts.from_args(args), args.output)
