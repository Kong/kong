.PHONY: changelog-generate changelog-regenerate

CHANGELOG_VERSION=1.0.0
CHANGELOG_FOLDER=unreleased
changelog-generate:
	@rm -f changelog/$(CHANGELOG_FOLDER)/$(CHANGELOG_VERSION).md
	@touch changelog/$(CHANGELOG_FOLDER)/$(CHANGELOG_VERSION).md
	@if [ -d "changelog/$(CHANGELOG_FOLDER)/kong" ]; then \
		changelog generate \
			--repo-path . \
			--changelog-paths changelog/$(CHANGELOG_FOLDER)/kong \
			--title Kong \
			--github-issue-repo Kong/kong \
			--github-api-repo Kong/kong \
			>> changelog/$(CHANGELOG_FOLDER)/$(CHANGELOG_VERSION).md; \
    fi
	@if [ -d "changelog/$(CHANGELOG_FOLDER)/kong-manager" ]; then \
		changelog generate \
			--repo-path . \
			--changelog-paths changelog/$(CHANGELOG_FOLDER)/kong-manager \
			--title Kong-Manager \
			--github-issue-repo Kong/kong-manager \
			--github-api-repo Kong/kong \
			>> changelog/$(CHANGELOG_FOLDER)/$(CHANGELOG_VERSION).md; \
    fi
	@echo "Successfully genreate changelog changelog/$(CHANGELOG_FOLDER)/$(CHANGELOG_VERSION).md"

CHANGELOG_VERSION=1.0.0
changelog-regenerate:
	@rm -f changelog/$(CHANGELOG_VERSION)/$(CHANGELOG_VERSION).md
	@touch changelog/$(CHANGELOG_VERSION)/$(CHANGELOG_VERSION).md
	@if [ -d "changelog/$(CHANGELOG_VERSION)/kong" ]; then \
		changelog generate \
			--repo-path . \
			--changelog-paths changelog/$(CHANGELOG_VERSION)/kong,changelog/unreleased/kong \
			--title Kong \
			--github-issue-repo Kong/kong \
			--github-api-repo Kong/kong \
			>> changelog/$(CHANGELOG_VERSION)/$(CHANGELOG_VERSION).md; \
    fi
	@if [ -d "changelog/$(CHANGELOG_VERSION)/kong-manager" ]; then \
		changelog generate \
			--repo-path . \
			--changelog-paths changelog/$(CHANGELOG_VERSION)/kong-manager,changelog/unreleased/kong-manager \
			--title Kong-Manager \
			--github-issue-repo Kong/kong-manager \
			--github-api-repo Kong/kong \
			>> changelog/$(CHANGELOG_VERSION)/$(CHANGELOG_VERSION).md; \
    fi
	@echo "Successfully re-genreate changelog changelog/$(CHANGELOG_VERSION)/$(CHANGELOG_VERSION).md"
