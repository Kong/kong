return [[
> local function render_changelog_entry(entry)
- ${entry.message}
>   if #(entry.prs or {}) > 0 then
>     for _, pr in ipairs(entry.prs or {}) do
 [${pr.name}](${pr.link})
>     end
>   end
>   if entry.jiras then
>     for _, jira in ipairs(entry.jiras or {}) do
  [${jira.id}](${jira.link})
>     end
>   end
>   if #(entry.issues or {}) > 0 then
(issue:
>     for _, issue in ipairs(entry.issues or {}) do
 [${issue.name}](${issue.link})
>     end
)
>   end
> end
>
> local function render_changelog_entries(entries)
>   for _, entry in ipairs(entries or {}) do
>     render_changelog_entry(entry)
>   end
> end
>
> local function render_changelog_section(section_name, t)
>   if #t.sorted_scopes > 0 then
### ${section_name}

>   end
>   for _, scope_name in ipairs(t.sorted_scopes or {}) do
>     if not (#t.sorted_scopes == 1 and scope_name == "Default") then -- do not print the scope_name if only one scope and it's Default scope
#### ${scope_name}

>     end
>     render_changelog_entries(t[scope_name])
>   end
> end
>
>
>
# ${version}

## Kong

> render_changelog_section("Breaking Changes", kong.breaking_changes)


> render_changelog_section("Deprecations", kong.deprecations)


> render_changelog_section("Dependencies", kong.dependencies)


> render_changelog_section("Features", kong.features)


> render_changelog_section("Fixes", kong.bugfixes)

]]
