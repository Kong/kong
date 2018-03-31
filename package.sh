#!/bin/bash

set -e

PLUGIN=`basename "$PWD"`
VERSION=`echo *.rockspec | sed "s/^.*-\([0-9.]*\.[0-9]*\.[0.-9]*-[0-9]*\)\.rockspec/\1/"`

#-------------------------------------------------------
# Remove existing archive directory and create a new one
#-------------------------------------------------------
rm -rf $PLUGIN || true
rm -f $PLUGIN-$VERSION.tar.gz || true
mkdir -p $PLUGIN

#----------------------------------------------
# Copy files to be archived to archive directory
#----------------------------------------------
cp -R ./kong $PLUGIN
cp INSTALL.txt README.md LICENSE *.rockspec $PLUGIN

#--------------
# Archive files
#--------------
tar cvzf $PLUGIN-$VERSION.tar.gz $PLUGIN

#-------------------------
# Remove archive directory
#-------------------------
rm -rf $PLUGIN || true

#-------------------------
# Create a rock
#-------------------------
luarocks make
luarocks pack $PLUGIN $VERSION
