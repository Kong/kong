.PHONY: generate

VERSION=3.x.y
FOLDER=unreleased
DEBUG=false
INCLUDE_UNRELEASED=false

generate:
	@rm -f $(VERSION).md
	@touch $(VERSION).md
	@if [ -d "$(FOLDER)/kong" ]; then \
		if [ "$(INCLUDE_UNRELEASED)" = "true" ]; then \
			changelog --debug=$(DEBUG) generate \
                --repo-path . \
                --changelog-paths $(FOLDER)/kong,unreleased/kong \
                --title Kong \
                --github-issue-repo Kong/kong \
                --github-api-repo Kong/kong \
                >> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
                --repo-path . \
                --changelog-paths $(FOLDER)/kong \
                --title Kong \
                --github-issue-repo Kong/kong \
                --github-api-repo Kong/kong \
                >> $(VERSION).md; \
        fi \
    fi
	@if [ -d "$(FOLDER)/kong-manager" ]; then \
		if [ "$(INCLUDE_UNRELEASED)" = "true" ]; then \
			changelog --debug=$(DEBUG) generate \
                --repo-path . \
                --changelog-paths $(FOLDER)/kong-manager,unreleased/manager \
                --title Kong-Manager \
                --github-issue-repo Kong/kong-manager \
                --github-api-repo Kong/kong \
                >> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
                --repo-path . \
                --changelog-paths $(FOLDER)/kong-manager \
                --title Kong-Manager \
                --github-issue-repo Kong/kong-manager \
                --github-api-repo Kong/kong \
                >> $(VERSION).md; \
		fi \
    fi
	@echo "Successfully genreate changelog $(VERSION).md"
