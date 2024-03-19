
import os
import re
from pathlib import Path

import lief
from looseversion import LooseVersion
from elftools.elf.elffile import ELFFile

caches = {}


def lazy_evaluate_cache():
    def decorator(fn):
        def wrapper(self, name):
            key = (self, name)
            if key in caches:
                return caches[key]
            r = fn(self, name)
            caches[key] = r
            return r
        return wrapper
    return decorator


class ExplainOpts():
    # General
    owners = True
    mode = True
    size = False
    # ELF
    arch = False
    merge_rpaths_runpaths = False
    imported_symbols = False
    exported_symbols = False
    version_requirement = False

    @classmethod
    def from_args(this, args):
        this.owners = args.owners
        this.mode = args.mode
        this.size = args.size
        this.arch = args.arch
        this.merge_rpaths_runpaths = args.merge_rpaths_runpaths
        this.imported_symbols = args.imported_symbols
        this.exported_symbols = args.exported_symbols
        this.version_requirement = args.version_requirement

        return this


class FileInfo():
    def __init__(self, path, relpath):
        self.path = path
        self.relpath = relpath

        self._lazy_evaluate_cache = {}
        self._lazy_evaluate_attrs = {}

        if Path(path).is_symlink():
            self.link = os.readlink(path)
        elif Path(path).is_dir():
            self.directory = True

        # use lstat to get the mode, uid, gid of the symlink itself
        self.mode = os.lstat(path).st_mode
        # unix style mode
        self.file_mode = '0' + oct(self.mode & 0o777)[2:]
        self.uid = os.lstat(path).st_uid
        self.gid = os.lstat(path).st_gid

        if not Path(path).is_symlink():
            self.size = os.stat(path).st_size

        self._lazy_evaluate_attrs.update({
            "binary_content": lambda: open(path, "rb").read(),
            "text_content": lambda: open(path, "rb").read().decode('utf-8'),
        })

    def __getattr__(self, name):
        if name in self._lazy_evaluate_cache:
            return self._lazy_evaluate_cache[name]

        ret = None
        if name in self._lazy_evaluate_attrs:
            ret = self._lazy_evaluate_attrs[name]()

        if ret:
            self._lazy_evaluate_cache[name] = ret
            return ret

        return self.__getattribute__(name)

    def explain(self, opts: ExplainOpts):
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

        self.arch = None
        self.needed_libraries = []
        self.rpath = None
        self.runpath = None
        self.get_exported_symbols = None
        self.get_imported_symbols = None
        self.version_requirement = {}

        if not os.path.isfile(path):
            return

        with open(path, "rb") as f:
            if f.read(4) != b"\x7fELF":
                return

        binary = lief.parse(path)
        if not binary:  # not an ELF file, malformed, etc
            return

        self.arch = binary.header.machine_type.name

        for d in binary.dynamic_entries:
            if d.tag == lief.ELF.DYNAMIC_TAGS.NEEDED:
                self.needed_libraries.append(d.name)
            elif d.tag == lief.ELF.DYNAMIC_TAGS.RPATH:
                self.rpath = d.name
            elif d.tag == lief.ELF.DYNAMIC_TAGS.RUNPATH:
                self.runpath = d.name

        # create closures and lazily evaluated
        self.get_exported_symbols = lambda: sorted(
            [d.name for d in binary.exported_symbols])
        self.get_imported_symbols = lambda: sorted(
            [d.name for d in binary.imported_symbols])
        self.get_functions = lambda: sorted(
            [d.name for d in binary.functions])

        for f in binary.symbols_version_requirement:
            self.version_requirement[f.name] = [LooseVersion(
                a.name) for a in f.get_auxiliary_symbols()]
            self.version_requirement[f.name].sort()

        self._lazy_evaluate_attrs.update({
            "exported_symbols": self.get_exported_symbols,
            "imported_symbols": self.get_imported_symbols,
            "functions": self.get_functions,
        })

    def explain(self, opts: ExplainOpts):
        pline = super().explain(opts)

        lines = []

        if opts.arch and self.arch:
            lines.append(("Arch", self.arch))
        if self.needed_libraries:
            lines.append(("Needed", self.needed_libraries))
        if self.rpath:
            lines.append(("Rpath", self.rpath))
        if self.runpath:
            lines.append(("Runpath", self.runpath))
        if opts.exported_symbols and self.get_exported_symbols:
            lines.append(("Exported", self.get_exported_symbols()))
        if opts.imported_symbols and self.get_imported_symbols:
            lines.append(("Imported", self.get_imported_symbols()))
        if opts.version_requirement and self.version_requirement:
            req = []
            for k in sorted(self.version_requirement):
                req.append("%s: %s" %
                           (k, ", ".join(map(str, self.version_requirement[k]))))
            lines.append(("Version Requirement", req))

        return pline + lines


class NginxInfo(ElfFileInfo):
    def __init__(self, path, relpath):
        super().__init__(path, relpath)

        # nginx must be an ELF file
        if not self.needed_libraries:
            return

        self.nginx_modules = []
        self.nginx_compiled_openssl = None
        self.nginx_compile_flags = None

        binary = lief.parse(path)

        for s in binary.strings:
            if re.match("\s*--prefix=/", s):
                self.nginx_compile_flags = s
                for m in re.findall("add(?:-dynamic)?-module=(.*?) ", s):
                    if m.startswith("../"):  # skip bundled modules
                        continue
                    pdir = os.path.basename(os.path.dirname(m))
                    mname = os.path.basename(m)
                    if pdir in ("external", "distribution"):
                        self.nginx_modules.append(mname)
                    else:
                        self.nginx_modules.append(os.path.join(pdir, mname))
                self.nginx_modules = sorted(self.nginx_modules)
            elif m := re.match("^built with (.+) \(running with", s):
                self.nginx_compiled_openssl = m.group(1).strip()

        # Fetch DWARF infos
        with open(path, "rb") as f:
            elffile = ELFFile(f)
            self.has_dwarf_info = elffile.has_dwarf_info()
            self.has_ngx_http_request_t_DW = False
            dwarf_info = elffile.get_dwarf_info()
            for cu in dwarf_info.iter_CUs():
                dies = [die for die in cu.iter_DIEs()]
                # Too many DIEs in the binary, we just check those in `ngx_http_request`
                if "ngx_http_request" in dies[0].attributes['DW_AT_name'].value.decode('utf-8'):
                    for die in dies:
                        value = die.attributes.get('DW_AT_name') and die.attributes.get(
                            'DW_AT_name').value.decode('utf-8')
                        if value and value == "ngx_http_request_t":
                            self.has_ngx_http_request_t_DW = True
                            return

    def explain(self, opts: ExplainOpts):
        pline = super().explain(opts)

        lines = []
        lines.append(("Modules", self.nginx_modules))
        lines.append(("OpenSSL", self.nginx_compiled_openssl))
        lines.append(("DWARF", self.has_dwarf_info))
        lines.append(("DWARF - ngx_http_request_t related DWARF DIEs",
                     self.has_ngx_http_request_t_DW))

        return pline + lines
