.PHONY: all create_branch generate push_changelog

VERSION ?= 3.6.0
BASE_BRANCH ?= origin/release/3.6.x
DEBUG ?= false
UNRELEASED_DIR := unreleased

BRANCH_NAME := generate-$(VERSION)-changelog

all: create_branch generate push_changelog

create_branch:
	@git fetch
	@git checkout -B $(BRANCH_NAME) $(BASE_BRANCH)

generate:
	@rm -f $(VERSION).md
	@touch $(VERSION).md

	@if [ -d "$(UNRELEASED_DIR)/kong" ]; then \
		if [ -f "$(VERSION)/$(VERSION).md" ]; then \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(VERSION)/kong,$(UNRELEASED_DIR)/kong \
				--title Kong \
				--github-issue-repo Kong/kong \
				--github-api-repo Kong/kong \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(UNRELEASED_DIR)/kong \
				--title Kong \
				--github-issue-repo Kong/kong \
				--github-api-repo Kong/kong \
				--with-jiras \
				>> $(VERSION).md; \
		fi \
	fi
	@if [ -d "$(UNRELEASED_DIR)/kong-manager" ]; then \
		if [ -f "$(VERSION)/$(VERSION).md" ]; then \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(VERSION)/kong-manager,$(UNRELEASED_DIR)/kong-manager \
				--title Kong-Manager \
				--github-issue-repo Kong/kong-manager \
				--github-api-repo Kong/kong \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(UNRELEASED_DIR)/kong-manager \
				--title Kong-Manager \
				--github-issue-repo Kong/kong-manager \
				--github-api-repo Kong/kong \
				--with-jiras \
				>> $(VERSION).md; \
		fi \
    fi

	@mv $(VERSION).md $(UNRELEASED_DIR)/
	@git mv $(UNRELEASED_DIR) $(VERSION)
	@mkdir -p $(UNRELEASED_DIR)/{kong,kong-manager}
	@touch $(UNRELEASED_DIR)/{kong,kong-manager}/.gitkeep

	@echo
	@echo "Done! Please check $(VERSION)/$(VERSION).md"

push_changelog:
	@git add .
	@git commit -m "docs(release): genereate $(VERSION) changelog"
	@git push -fu origin HEAD

	@echo
	@echo "Successfully pushed $(BRANCH_NAME) to Github. Please create changelog PR overthere."