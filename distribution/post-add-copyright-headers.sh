#!/usr/bin/env bash

#####
#
# add the copyright header to html/js(.map)/css files
#
# this must come after admin and portal installation
#
#####

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

source .requirements

function main() {
    echo '--- installing copyright headers ---'

    first_line="$(
      sed -n -e 's/^-- //g;1p' /distribution/COPYRIGHT-HEADER
    )"

    admin_directory="${KONG_ADMIN_DIRECTORY:-gui}"
    portal_directory="${KONG_PORTAL_DIRECTORY:-portal}"

    find \
      "/tmp/build/usr/local/kong/${admin_directory}" \
      "/tmp/build/usr/local/kong/${portal_directory}" \
      -type f \
      \( \
        -name "*.js" -o \
        -name "*.html" -o \
        -name "*.map" -o \
        -name "*.css" \
      \) \
      -print \
        | while read -r file_path; do

          if grep -qs "$first_line" "$file_path"; then
            echo "header already present in ${file_path}"
            continue
          fi

          temporary="$(mktemp)"

          if [[ "$file_path" == *'.html' ]]; then
            open_comment='<!--'
            close_comment=$'-->\n\n'
          else
            open_comment='/*'
            close_comment=$'*/\n\n'
          fi

          # add open/header/close/OG content and move to OG path
          {
            echo "$open_comment"
            sed -e 's/^-- /  /g' /distribution/COPYRIGHT-HEADER
            echo "$close_comment"
            cat < "$file_path"
          } > "$temporary"

          mv -f "$temporary" "$file_path"

          # spacing to match "already present" message above
          echo "header added to           ${file_path}"

        done

    echo '--- installed copyright headers ---'
}

main
