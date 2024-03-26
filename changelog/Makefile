# SHELL := $(shell which bash)
# $(info Use shell $(SHELL))

OWNER_REPO := Kong/kong
BASE_BRANCH ?= release/3.6.x
VERSION ?= 3.6.0
DEBUG ?= false
UNRELEASED_DIR ?= unreleased

BRANCH_NAME := generate-$(VERSION)-changelog
ORIGIN_BRANCH := origin/$(BASE_BRANCH)

.PHONY: all check_tools check_version create_branch generate push_changelog create_pr

all: check_tools check_version create_branch generate push_changelog create_pr
no_pr: check_tools check_version create_branch generate push_changelog

REQUIRED_TOOLS := git changelog curl jq
check_tools:
	$(foreach cmd,$(REQUIRED_TOOLS), \
		$(if $(shell command -v $(cmd) 2>/dev/null), $(info $(cmd) found), \
			$(error command '$(cmd)' command not found) \
		) \
	)
ifndef GITHUB_TOKEN
	$(error environment variable GITHUB_TOKEN not found)
else
	$(info GITHUB_TOKEN found)
endif

BINARY_VERSION := $(shell changelog -v | awk '{print $$3}')
BAD_VERSION := 0.0.1
REQUIRED_VERSION := 0.0.2
check_version:
	@if [ $(BINARY_VERSION) = $(BAD_VERSION) ] ; then \
		echo "changelog version is $(BINARY_VERSION). Upgrade to $(REQUIRED_VERSION) at least." ; \
		false ; \
	else \
		echo "all required tools satisfied" ; \
	fi

create_branch:
	@git fetch --prune
	@git submodule update --init --recursive
	@git checkout -B $(BRANCH_NAME) $(ORIGIN_BRANCH)

generate:
	@rm -f $(VERSION).md
	@touch $(VERSION).md

	@if [ -n "$$(shopt -s nullglob; echo $(UNRELEASED_DIR)/kong/*.yml)" ] || \
		[ -n "$$(shopt -s nullglob; echo $(VERSION)/kong/*.yml)" ] ; then \
		changelog --debug=$(DEBUG) generate \
			--repo-path . \
			--changelog-paths $(VERSION)/kong,$(UNRELEASED_DIR)/kong \
			--title Kong \
			--github-issue-repo $(OWNER_REPO) \
			--github-api-repo $(OWNER_REPO) \
			--with-jiras \
			>> $(VERSION).md; \
	fi
	@if [ -n "$$(shopt -s nullglob; echo $(UNRELEASED_DIR)/kong-manager/*.yml)" ] || \
		[ -n "$$(shopt -s nullglob; echo $(VERSION)/kong-manager/*.yml)" ] ; then \
		changelog --debug=$(DEBUG) generate \
			--repo-path . \
			--changelog-paths $(VERSION)/kong-manager,$(UNRELEASED_DIR)/kong-manager \
			--title Kong-Manager \
			--github-issue-repo Kong/kong-manager \
			--github-api-repo $(OWNER_REPO) \
			--with-jiras \
			>> $(VERSION).md; \
    fi

	@echo
	@echo "Please inspect $(VERSION).md"

push_changelog:
	@mkdir -p $(VERSION)
	@mv -f $(VERSION).md $(VERSION)/
	@for i in kong kong-manager ; do \
		mkdir -p $(UNRELEASED_DIR)/$$i ; \
		mkdir -p $(VERSION)/$$i ; \
		git mv -k $(UNRELEASED_DIR)/$$i/*.yml $(VERSION)/$$i/ ; \
		touch $(UNRELEASED_DIR)/$$i/.gitkeep ; \
		touch $(VERSION)/$$i/.gitkeep ; \
	done
	@git add .
	@git commit -m "docs(release): genereate $(VERSION) changelog"
	@git push -fu origin HEAD

	@echo
	@echo "Successfully updated $(BRANCH_NAME) to GitHub."

create_pr:
	@bash create_pr $(OWNER_REPO) $(BASE_BRANCH) $(VERSION) $(BRANCH_NAME)
