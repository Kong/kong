#!/bin/bash

if ! [[ "$TRAVIS_BRANCH" == "master" || "$TRAVIS_BRANCH" == "next" ]] ; then
  exit 0
fi

pip install datadog
cat >~/.dogrc <<EOL
[Connection]
apikey = $DD_API_KEY
appkey = $DD_APP_KEY
EOL

cat ~/output/* | grep 'FAILED  ' | grep -v listed | grep -v ms > collated_output.txt
sed 's/^.*spec\///; s/\.lua.*$//' collated_output.txt | sed 's/^//' > parsed_output.txt
sed 's/-/_/g' parsed_output.txt | sed 's/[^a-zA-Z0-9_]/\./g' > dd_compatible.txt
<dd_compatible.txt xargs -I % dog metric post travis_ci.kong.failure --type count --tags "test:%" 1
