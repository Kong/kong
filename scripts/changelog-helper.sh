#!/bin/bash

read -r -d '' __USAGE <<'EOF'

Usage: $(basename $0) -t <token> -f <tag_from>

Options:
  -t, <token>     Github token. See https://github.com/settings/tokens . It only needs 'repo' scopes, without security_events.
  -f, <tag_from>  The tag from which to compare master to obtain the diff

** NOTE: Github limits the number of commits to 250. If the diff is bigger, you will get less commits than you should **

Requirements: curl, jq

EOF

while getopts f:t: flag
do
    case "${flag}" in
        f) TAG_FROM=${OPTARG};;
        t) GITHUB_TOKEN=${OPTARG};;
        *) echo "Invalid flag: ${flag}"; exit 1;;
    esac
done

if [ -z "$GITHUB_TOKEN" ] || [ -z "$TAG_FROM" ]; then
    echo "$__USAGE"
    exit 1
fi

curl -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/kong/kong/compare/$TAG_FROM...master" | \
  jq '[.commits| .[] | {message: .commit.message, author: .author.login}]'


