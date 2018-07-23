#!/usr/bin/env bash

make dev
/kong/bin/kong prepare
/kong/bin/kong migrations up && tail -f /dev/null