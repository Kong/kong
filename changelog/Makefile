.PHONY: generate_changelog push_changelog

VERSION = 3.x.y.z
UNRELEASED_DIR = unreleased
DEBUG = false

generate_changelog:
	@rm -f $(VERSION).md
	@touch $(VERSION).md

	@if [ -d "$(UNRELEASED_DIR)/kong" ]; then \
		if [ -f "$(VERSION)/$(VERSION).md" ]; then \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(VERSION)/kong,$(UNRELEASED_DIR)/kong \
				--title Kong \
				--github-issue-repo Kong/kong \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(UNRELEASED_DIR)/kong \
				--title Kong \
				--github-issue-repo Kong/kong \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		fi \
	fi
	@if [ -d "$(UNRELEASED_DIR)/kong-ee" ]; then \
		if [ -f "$(VERSION)/$(VERSION).md" ]; then \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(VERSION)/kong-ee,$(UNRELEASED_DIR)/kong-ee \
				--title Kong-Enterprise \
				--github-issue-repo Kong/kong-ee \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(UNRELEASED_DIR)/kong-ee \
				--title Kong-Enterprise \
				--github-issue-repo Kong/kong-ee \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		fi \
    fi
	@if [ -d "$(UNRELEASED_DIR)/kong-manager-ee" ]; then \
		if [ -f "$(VERSION)/$(VERSION).md" ]; then \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(VERSION)/kong-manager-ee,$(UNRELEASED_DIR)/kong-manager-ee \
				--title Kong-Manager-Enterprise \
				--github-issue-repo Kong/kong-admin \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(UNRELEASED_DIR)/kong-manager-ee \
				--title Kong-Manager-Enterprise \
				--github-issue-repo Kong/kong-admin \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		fi \
    fi
	@if [ -d "$(UNRELEASED_DIR)/kong-portal-ee" ]; then \
		if [ -f "$(VERSION)/$(VERSION).md" ]; then \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(VERSION)/kong-portal-ee,$(UNRELEASED_DIR)/kong-portal-ee \
				--title Kong-Portal \
				--github-issue-repo Kong/kong-portal-templates \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		else \
			changelog --debug=$(DEBUG) generate \
				--repo-path . \
				--changelog-paths $(UNRELEASED_DIR)/kong-portal-ee \
				--title Kong-Portal \
				--github-issue-repo Kong/kong-portal-templates \
				--github-api-repo Kong/kong-ee \
				--with-jiras \
				>> $(VERSION).md; \
		fi \
    fi

	@mv $(VERSION).md $(UNRELEASED_DIR)/
	@git mv $(UNRELEASED_DIR) $(VERSION)
	@mkdir -p $(UNRELEASED_DIR)/{kong,kong-ee,kong-manager-ee,kong-portal-ee}
	@touch $(UNRELEASED_DIR)/{kong,kong-ee,kong-manager-ee,kong-portal-ee}/.gitkeep

	@echo
	@echo "Done! Please check $(VERSION)/$(VERSION).md"

BRANCH_BASE = origin/next/3.x.x.x
push_changelog:
	@git checkout -b generate-$(VERSION)-changelog $(BRANCH_BASE)
	@git add .
	@git commit -m "docs(release): genereate $(VERSION) changelog"
	@git push -u origin HEAD

	@echo
	@echo "Successfully push changelog Github. Please create PR overthere."