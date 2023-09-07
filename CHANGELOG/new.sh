#!/bin/bash
set -e

echo "What is this changelog for (kong, kong-ee, kong-manager)?"
select component in kong kong-ee kong-manager; do
    case $component in
        kong|kong-ee|kong-manager) break;;
        *) echo "Invalid option. Please select again.";;
    esac
done

echo

read -p "What is the title of the change? " title

echo

echo "What is the type of the change (feature, bugfix, dependency, deprecation, breaking_change, performance)?"
select type in feature bugfix dependency deprecation breaking_change performance; do
    case $type in
        feature|bugfix|dependency|deprecation|breaking_change|performance) break;;
        *) echo "Invalid option. Please select again.";;
    esac
done

echo

echo "What is the scope of the change (Core, Plugin, PDK, Admin API, Performance, Configuration, Clustering)?"
select scope in Core Plugin PDK "Admin API" Performance Configuration Clustering; do
    case $scope in
        Core|Plugin|PDK|"Admin API"|Performance|Configuration|Clustering) break;;
        *) echo "Invalid option. Please select again.";;
    esac
done

echo

read -p "What are the associated PRs? (comma-separated, without spaces e.g. 123,124,125) " pr_input
IFS=',' read -ra prs <<< "$pr_input"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
file_name="$SCRIPT_DIR/unreleased/$component/${prs[0]:-unknown}.yml"

echo

echo "New changelog will be created at $file_name"

echo

read -p "What are the associated Jira tickets? (comma-separated, without spaces e.g. FTI-123,FTI-124) " jira_input
IFS=',' read -ra jiras <<< "$jira_input"

echo

read -p "What are the associated issues? (comma-separated, without spaces e.g. 123,124,125) " issue_input
IFS=',' read -ra issues <<< "$issue_input"

echo "message: $title" > $file_name
echo "type: $type" >> $file_name
echo "scope: $scope" >> $file_name
echo "prs:" >> $file_name
for pr in "${prs[@]}"; do
    echo "  - $pr" >> $file_name
done
echo "jiras:" >> $file_name
for jira in "${jiras[@]}"; do
    echo "  - \"$jira\"" >> $file_name
done
echo "issues:" >> $file_name
for issue in "${issues[@]}"; do
    echo "  - $issue" >> $file_name
done

echo

echo "Changelog file generated as $file_name:"
echo "Be sure to \"git add\" and \"git commit\" this file"
echo "================================================================"
cat $file_name
