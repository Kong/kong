#!/bin/bash

set -ex

echo "${SLACK_MESSAGE}"
curl -X POST -H 'Content-type: application/json' --data '{"text": '"'${SLACK_MESSAGE}'"'}' "${SLACK_WEBHOOK}"

