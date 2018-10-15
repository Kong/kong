#!/bin/bash

pip install datadog
cat >~/.dogrc <<EOL
[Connection]
apikey = $DD_API_KEY
appkey = $DD_APP_KEY
EOL

cat ~/output/* | grep 'FAILED  ' | grep -v listed | grep -v ms > collated_output.txt
cat collated_output.txt | sed 's/^.*spec\///; s/\.lua.*$//' | sed 's/^/travis_ci.kong.failure./' > parsed_output.txt
cat parsed_output.txt | sed 's/-/_/g' | sed 's/[^a-zA-Z0-9_]/\./g' > dd_compatible.txt
<dd_compatible.txt xargs -I % dog metric post % 1
