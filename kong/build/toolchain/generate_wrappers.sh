#!/bin/bash -e

name=$1
wrapper=$2
prefix=$3
dummy_file=$4

if [[ -z $name || -z $wrapper || -z $prefix ]]; then
    echo "Usage: $0 <name> <wrapper> <prefix>"
    exit 1
fi

cwd=$(realpath $(dirname $(readlink -f ${BASH_SOURCE[0]})))
dir=wrappers-$name
mkdir -p $cwd/$dir
cp $wrapper $cwd/$dir/
chmod 755 $cwd/$dir/wrapper

pushd $cwd/$dir >/dev/null

tools="addr2line ar as c++ cc@ c++filt cpp dwp elfedit g++ gcc gcc-ar gcc-nm gcc-ranlib gcov gcov-dump gcov-tool gfortran gprof ld ld.bfd ld.gold lto-dump nm objcopy objdump ranlib readelf size strings strip"
for tool in $tools; do
    ln -sf wrapper $prefix$tool
done

popd >/dev/null

if [[ -n $dummy_file ]]; then
    touch $dummy_file
fi

