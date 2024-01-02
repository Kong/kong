#!/bin/bash
git switch flaky-index
echo $(date) > flaky-traker/ci-trigger.log
git add flaky-traker/ci-trigger.log
git commit -m "automation(test): Triggering CI build"
git push origin flaky-index
