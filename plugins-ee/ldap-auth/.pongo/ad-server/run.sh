#!/bin/bash 

set -e

echo "Setting up samba"
source /setup/setup.sh
echo "Seeding with data"
source /setup/add-seed-data.sh
echo "Getting samba version"
samba -V -b
exec "$@"