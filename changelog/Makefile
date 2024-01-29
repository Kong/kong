.PHONY: generate

VERSION=3.x.y.z
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
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(FOLDER)/kong \
				--title Kong \
				--github-issue-repo Kong/kong \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
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
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(FOLDER)/kong-manager \
				--title Kong-Manager \
				--github-issue-repo Kong/kong-manager \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		fi \
	fi
	@if [ -d "$(FOLDER)/kong-ee" ]; then \
		if [ "$(INCLUDE_UNRELEASED)" = "true" ]; then \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(FOLDER)/kong-ee,unreleased/kong-ee \
				--title Kong-Enterprise \
				--github-issue-repo Kong/kong-ee \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(FOLDER)/kong-ee \
				--title Kong-Enterprise \
				--github-issue-repo Kong/kong-ee \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		fi \
    fi
	@if [ -d "$(FOLDER)/kong-manager-ee" ]; then \
		if [ "$(INCLUDE_UNRELEASED)" = "true" ]; then \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(FOLDER)/kong-manager-ee,unreleased/kong-manager-ee \
				--title Kong-Manager-Enterprise \
				--github-issue-repo Kong/kong-admin \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(FOLDER)/kong-manager-ee \
				--title Kong-Manager-Enterprise \
				--github-issue-repo Kong/kong-admin \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		fi \
    fi
	@if [ -d "$(FOLDER)/kong-portal-ee" ]; then \
		if [ "$(INCLUDE_UNRELEASED)" = "true" ]; then \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(FOLDER)/kong-portal-ee,unreleased/kong-portal-ee \
				--title Kong-Portal \
				--github-issue-repo Kong/kong-portal-templates \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(FOLDER)/kong-portal-ee \
				--title Kong-Portal \
				--github-issue-repo Kong/kong-portal-templates \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		fi \
    fi
	@echo "Successfully genreate changelog $(VERSION).md"
