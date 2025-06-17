#!/bin/bash -e

# template variables starts
libexpat_path="{{@@libexpat//:libexpat}}"
libxml2_path="invalid"
openssl_path="{{@@openssl//:openssl}}"
luarocks_host_path="{{@@luarocks//:luarocks_host}}"
luajit_path="{{@@openresty//:luajit}}"
kongrocks_path="invalid"
cross_deps_libyaml_path="{{@@cross_deps_libyaml//:libyaml}}"
CC={{CC}}
LD={{LD}}
LIB_RPATH={{lib_rpath}}
# template variables ends

root_path=$(pwd)

ROCKS_DIR=$root_path/$(dirname $@)/luarocks_tree
if [ ! -d $ROCKS_DIR ]; then
    mkdir -p $ROCKS_DIR
fi
# pre create the dir and file so bsd readlink is happy
mkdir -p "$ROCKS_DIR/../cache"
CACHE_DIR=$(readlink -f "$ROCKS_DIR/../cache")
touch "$ROCKS_DIR/../luarocks_config.lua"
ROCKS_CONFIG=$(readlink -f "$ROCKS_DIR/../luarocks_config.lua")

EXPAT_DIR=$root_path/$libexpat_path
LIBXML2_DIR=$root_path/$libxml2_path
OPENSSL_DIR=$root_path/$openssl_path

# The Bazel rules doesn't export the `libexpat.so` file,
# it only exports something like `libexpat.so.1.6.0`,
# but the linker expects `libexpat.so` to be present.
# So we create a symlink to the actual file
# if it doesn't exist.
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS uses `.dylib``
    if ! test -e $EXPAT_DIR/lib/libexpat.dylib; then
        dylib=$(ls $EXPAT_DIR/lib/libexpat.*)
        if [[ -z $dylib ]]; then
            echo "No expat library found in $EXPAT_DIR/lib"
            exit 1
        fi
        ln -s $dylib $EXPAT_DIR/lib/libexpat.dylib
    fi
else
    # Linux uses `.so``
    if ! test -e $EXPAT_DIR/lib/libexpat.so; then
        so=$(ls $EXPAT_DIR/lib/libexpat.*)
        if [[ -z $so ]]; then
            echo "No expat library found in $EXPAT_DIR/lib"
            exit 1
        fi
        ln -s $so $EXPAT_DIR/lib/libexpat.so
    fi
fi

# we use system libyaml on macos
if [[ "$OSTYPE" == "darwin"* ]]; then
     YAML_DIR=$(HOME=~$(whoami) PATH=/opt/homebrew/bin:$PATH brew --prefix)/opt/libyaml
elif [[ -d $cross_deps_libyaml_path ]]; then
    # TODO: is there a good way to use locations but doesn't break non-cross builds?
    YAML_DIR=$root_path/$cross_deps_libyaml_path
else
    YAML_DIR=/usr
fi

if [[ $CC != /* ]]; then
    # point to our relative path of managed toolchain
    CC=$root_path/$CC
    LD=$root_path/$LD
fi

echo "
rocks_trees = {
    { name = [[system]], root = [[$ROCKS_DIR]] }
}
local_cache = '$CACHE_DIR'
show_downloads = true
gcc_rpath = false -- disable default rpath, add our own
variables = {
    CC = '$CC',
    LD = '$LD',
    LDFLAGS = '-Wl,-rpath,$LIB_RPATH',
}
" > $ROCKS_CONFIG

LUAROCKS_HOST=$luarocks_host_path

host_luajit=$root_path/$luajit_path/bin/luajit

cat << EOF > $@
LIB_RPATH=$LIB_RPATH
LUAROCKS_HOST=$LUAROCKS_HOST
ROCKS_DIR=$ROCKS_DIR
CACHE_DIR=$CACHE_DIR
ROCKS_CONFIG=$ROCKS_CONFIG

export LUAROCKS_CONFIG=$ROCKS_CONFIG
export CC=$CC
export LD=$LD

# no idea why PATH is not preserved in ctx.actions.run_shell
export PATH=$PATH

if [[ $kongrocks_path == external* ]]; then
    p=$root_path/external/kongrocks/rocks
    echo "Using bundled rocks from \$p"
    echo "If errors like 'No results matching query were found for Lua 5.1.' are shown, submit a PR to https://github.com/kong/kongrocks"
    private_rocks_args="--only-server \$p"
fi

# force the interpreter here instead of invoking luarocks directly,
# some distros has BINPRM_BUF_SIZE smaller than the shebang generated,
# which is usually more than 160 bytes
$host_luajit $root_path/$LUAROCKS_HOST/bin/luarocks \$private_rocks_args \$@ \\
    OPENSSL_DIR=$OPENSSL_DIR \\
    CRYPTO_DIR=$OPENSSL_DIR \\
    EXPAT_DIR=$EXPAT_DIR \\
    LIBXML2_DIR=$LIBXML2_DIR \\
    YAML_DIR=$YAML_DIR
EOF
