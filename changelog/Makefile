.PHONY: changelog-generate changelog-regenerate

CHANGELOG_VERSION=1.0.0
CHANGELOG_FOLDER=unreleased
changelog-generate:
	@rm -f $(CHANGELOG_FOLDER)/$(CHANGELOG_VERSION).md
	@touch $(CHANGELOG_FOLDER)/$(CHANGELOG_VERSION).md
	@if [ -d "$(CHANGELOG_FOLDER)/kong" ]; then \
		changelog generate \
			--repo-path . \
			--changelog-paths $(CHANGELOG_FOLDER)/kong \
			--title Kong \
			--github-issue-repo Kong/kong \
			--github-api-repo Kong/kong \
			>> $(CHANGELOG_FOLDER)/$(CHANGELOG_VERSION).md; \
    fi
	@if [ -d "$(CHANGELOG_FOLDER)/kong-manager" ]; then \
		changelog generate \
			--repo-path . \
			--changelog-paths $(CHANGELOG_FOLDER)/kong-manager \
			--title Kong-Manager \
			--github-issue-repo Kong/kong-manager \
			--github-api-repo Kong/kong \
			>> $(CHANGELOG_FOLDER)/$(CHANGELOG_VERSION).md; \
    fi
	@echo "Successfully genreate changelog $(CHANGELOG_FOLDER)/$(CHANGELOG_VERSION).md"

CHANGELOG_VERSION=1.0.0
changelog-regenerate:
	@rm -f $(CHANGELOG_VERSION)/$(CHANGELOG_VERSION).md
	@touch $(CHANGELOG_VERSION)/$(CHANGELOG_VERSION).md
	@if [ -d "$(CHANGELOG_VERSION)/kong" ]; then \
		changelog generate \
			--repo-path . \
			--changelog-paths $(CHANGELOG_VERSION)/kong,unreleased/kong \
			--title Kong \
			--github-issue-repo Kong/kong \
			--github-api-repo Kong/kong \
			>> $(CHANGELOG_VERSION)/$(CHANGELOG_VERSION).md; \
    fi
	@if [ -d "$(CHANGELOG_VERSION)/kong-manager" ]; then \
		changelog generate \
			--repo-path . \
			--changelog-paths $(CHANGELOG_VERSION)/kong-manager,unreleased/kong-manager \
			--title Kong-Manager \
			--github-issue-repo Kong/kong-manager \
			--github-api-repo Kong/kong \
			>> $(CHANGELOG_VERSION)/$(CHANGELOG_VERSION).md; \
    fi
	@echo "Successfully re-genreate changelog $(CHANGELOG_VERSION)/$(CHANGELOG_VERSION).md"
