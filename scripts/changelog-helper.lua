#!/usr/bin/env resty
setmetatable(_G, nil)

local cjson = require "cjson"
local http = require "resty.http"

local USAGE = [[
  Usage:

  scripts/changelog-helper.lua <from_ref> <to_ref> <token>

  Example:

  scripts/changelog-helper.lua 2.4.1 master $GITHUB_TOKEN

  For the Github token, visit https://github.com/settings/tokens . It only needs "public_repo" and "read:org" scopes.

  ** NOTE: Github limits the number of commits to compare to 250. If the diff is bigger, you will get an error, and will have to do the changelog manually **
]]


local KNOWN_KONGERS = { -- include kong alumni here
  hishamhm = true,
  p0pr0ck5 = true,
}

local fmt = string.format

local new_github_api = function(github_token)
  local get
  get = function(path)
    local httpc = assert(http.new())
    httpc:set_timeout(10000)

    -- The prefix "https://api.github.com" is optional. Add it to the path if not present
    if not path:match("^https:%/%/api%.github%.com%/.*$") then
      path = fmt("https://api.github.com%s", path)
    end

    local res = assert(httpc:request_uri(path, {
      method = "GET",
      ssl_verify = false,
      headers = {
        ["Authorization"] = fmt("token %s", github_token),
        -- needed to get prs associated to sha (/repos/kong/kong/commits/%s/pulls):
        ["Accept"] = "application/vnd.github.groot-preview+json",
      }
    }))
    -- recursively follow redirects
    if res.status == 302 and res.headers.Location then
      return get(res.headers.Location)
    end

    local body = res.body
    if body and body ~= "" then
      body = cjson.decode(body)
    end

    return body, res.status, res.headers
  end

  return { get = get }
end


local function get_comparison_commits(api, from_ref, to_ref)
  print("\n\nGetting comparison commits")
  local compare_res = api.get(fmt("/repos/kong/kong/compare/%s...%s", from_ref, to_ref))

  --[[
  if #compare_res.commits >= 250 then
    error("250 commits or more found on compare. Github only shows 250 on its compare query, so the comparison likely is missing data. Aborting in order to not produce incomplete results")
  end
  ]]

  return compare_res.commits
end


local function get_prs_from_comparison_commits(api, commits)
  local prs = {}
  local non_pr_commits = {}
  local pr_by_commit_sha = {}

  print("\n\nGetting PRs associated to commits in main comparison")
  local prs_res, pr
  for i, commit in ipairs(commits) do
    pr = pr_by_commit_sha[commit.sha]
    if not pr then
      prs_res = api.get(fmt("/repos/kong/kong/commits/%s/pulls", commit.sha))
      -- FIXME find a more appropiate pr from the list in pr_res. Perhaps using to_ref ?
      if type(prs_res[1]) == "table" then
        pr = prs_res[1]
      else
        non_pr_commits[#non_pr_commits + 1] = commit
        io.stdout:write(" !", commit.sha)
        io.stdout:flush()
      end
    end

    if pr then
      if not prs[pr.number] then
        prs[pr.number] = pr
        io.stdout:write(" #", pr.number)

        -- optimization: preload all commits for this PR into pr_by_commit_sha to avoid unnecessary calls to /repos/kong/kong/commits/%s/pulls
        local pr_commits_res = api.get(fmt("/repos/kong/kong/pulls/%d/commits?per_page=100", pr.number))
        for _, pr_commit in ipairs(pr_commits_res) do
          pr_by_commit_sha[pr_commit.sha] = pr
        end
      end
      pr.commits = pr.commits or {}
      pr.commits[#pr.commits + 1] = commit
      io.stdout:write(".")
      io.stdout:flush()
    end
  end

  return prs, non_pr_commits
end


local function get_non_konger_authors(api, commits)
  print("\n\nFinding non-konger authors")
  local author_logins_hash = {}
  for i, commit in ipairs(commits) do
    if type(commit.author) == "table" then -- can be null
      author_logins_hash[commit.author.login] = true
    end
  end

  local non_kongers = {}
  for login in pairs(author_logins_hash) do
    io.stdout:write(" ", login, ":")
    if KNOWN_KONGERS[login] then
      io.stdout:write("🦍")
    else
      local _, status = api.get(fmt("/orgs/kong/memberships/%s", login))
      if status == 404 then
        non_kongers[login] = true
        io.stdout:write("✅")
      else
        io.stdout:write("🦍")
      end
    end
    io.stdout:flush()
  end

  return non_kongers
end


local function extract_type_and_scope_and_title(str)
  local typ, scope, title = string.match(str, "^([^%(]+)%(([^%)]+)%) (.+)$")
  return typ, scope, title
end


local function get_first_line(str)
  return str:match("^([^\n]+)")
end

-- Transforms the list of PRs into a shorter table that is easier to get a report out of
local function categorize_prs(prs)
  print("\n\nCategorizing PRs")
  local categorized_prs = {}
  local commits, authors_hash
  for pr_number,pr in pairs(prs) do
    commits = {}
    authors_hash = {}
    for _,c in ipairs(pr.commits) do
      if c.author and c.author.login then
        authors_hash[c.author.login] = true
      end
      commits[#commits + 1] = c.commit.message
    end

    local typ, scope, title = extract_type_and_scope_and_title(pr.title)
    -- when pr title does not follow the "type(scope) title" format, use the last commit on the PR to extract type & scope
    if not typ then
      title = pr.title
      typ, scope = extract_type_and_scope_and_title(commits[#commits])
      if not typ then
        typ, scope = "unknown", "unknown"
      end
    end

    local authors = {}
    for a in pairs(authors_hash) do
      authors[#authors + 1] = a
    end
    table.sort(authors)

    categorized_prs[pr_number] = {
      number = pr_number,
      title = title,
      typ = typ,
      scope = scope,
      url = pr.html_url,
      description = pr.body,
      commits = commits,
      authors = authors,
    }
  end

  return categorized_prs
end

-- to_sentence({}) = ""
-- to_sentence({"a"}) = "a"
-- to_sentence({"a", "b"}) = "a and b"
-- to_sentence({"a", "b", "c" }) = "a, b and c"
local function to_sentence(arr)
  local buffer = {}
  local len = #arr
  for i = 1, len do
    buffer[i * 2 - 1] = arr[i]
    if i < len - 1 then
      buffer[i * 2] = ", "
    elseif i == len - 1 then
      buffer[i * 2] = " and "
    end
  end
  return table.concat(buffer)
end

local function render_pr_li_thank_you(authors, non_kongers_hash)
  local non_kongers_links = {}
  for _,login in ipairs(authors) do
    if non_kongers_hash[login] then
      non_kongers_links[#non_kongers_links + 1] = fmt("[%s](https://github.com/%s)", login, login)
    end
  end
  if #non_kongers_links == 0 then
    return "."
  end
  return fmt("\n  Thanks %s for the patch!", to_sentence(non_kongers_links))
end

local function render_pr_li_markdown(pr, non_kongers_hash)
  return fmt([[
- %s
  [#%d](%s)%s
]], pr.title, pr.number, pr.url, render_pr_li_thank_you(pr.authors, non_kongers_hash))
end


local function print_report(categorized_prs, non_pr_commits, non_kongers_hash, to_ref)
  local pr_numbers = {}
  for pr_number in pairs(categorized_prs) do
    pr_numbers[#pr_numbers + 1] = pr_number
  end
  table.sort(pr_numbers)

  print("=================================================")

  local pr
  -- Dependencies
  local first_dep = true
  for _,pr_number in ipairs(pr_numbers) do
    pr = categorized_prs[pr_number]

    if pr.typ == "chore" and (pr.scope == "deps" or pr.scope == "rockspec") then
      if first_dep then
        first_dep = false
        print("\n\n### Dependencies\n")
      end
      pr.reported = true
      print(render_pr_li_markdown(pr, non_kongers_hash))
    end
  end


  local categories_markdown = [[
##### Core

##### CLI

##### Configuration

##### Admin API

##### PDK

##### Plugins
  ]]

  local feats = {}
  local fixes = {}
  local unknown = {}
  for _,pr_number in ipairs(pr_numbers) do
    pr = categorized_prs[pr_number]
    if pr.typ == "feat" then
      feats[#feats + 1] = pr
    elseif pr.typ == "fix" then
      fixes[#fixes + 1] = pr
    elseif not pr.reported then
      unknown[#unknown + 1] = pr
    end
  end

  local sort_by_scope = function(a,b)
    if a.scope == b.scope then
      return a.number < b.number
    end
    return a.scope < b.scope
  end
  table.sort(feats, sort_by_scope)
  table.sort(fixes, sort_by_scope)
  table.sort(unknown, sort_by_scope)

  for i,pr in ipairs(feats) do
    if i == 1 then
      print([[


### Additions

Note: Categorize the additions below into one of these categories (add categories if needed).
      Remove this note

]], categories_markdown)
    end
    print(render_pr_li_markdown(pr, non_kongers_hash))
  end

  for i,pr in ipairs(fixes) do
    if i == 1 then
      print([[


### Fixes

Note: Categorize the fixes below into one of these categories (add categories if needed).
      Remove this note

]], categories_markdown)
    end
    print(render_pr_li_markdown(pr, non_kongers_hash))
  end


  for i,pr in ipairs(unknown) do
    if i == 1 then
      print([[


### Unknown PRs

The following PRs could not be identified as either fixes or feats. Please move them to their appropiate place or discard them.
Remove this whole section afterwards.

]])
    end

    print(fmt([[
- %s
  [#%d](%s)%s.
  Categorization: %s(%s)
  Commits:]],
  pr.title, pr.number, pr.url, render_pr_li_thank_you(pr.authors, non_kongers_hash), pr.typ, pr.scope))

    for j, commit in ipairs(pr.commits) do
      print(fmt([[
  - %s]], get_first_line(commit)))
    end
  end


  for i,commit in ipairs(non_pr_commits) do
    if i == 1 then
      print(fmt([[

### Non-PR commits

I could not find the PR for the following commits. They are likely direct pushes against %s.

]], to_ref))
    end

    local msg = commit.commit.message
    local typ, scope = extract_type_and_scope_and_title(msg)
    if not typ then
      typ, scope = "unknown", "unknown"
    end
    local author = commit.author and (commit.author.login or commit.author.name) or "unknown"

    print(fmt([[
- %s
  [%s](%s)
  Categorization: %s(%s)
  Author: %s
]], get_first_line(msg), commit.sha, commit.html_url, typ, scope, author))
  end

end



-----------------------

local from_ref, to_ref, github_token = arg[1], arg[2], arg[3]

if not from_ref or not to_ref or not github_token then
  print(USAGE)
  os.exit(0)
end

local api = new_github_api(github_token)

local commits = get_comparison_commits(api, from_ref, to_ref)

local prs, non_pr_commits = get_prs_from_comparison_commits(api, commits)

local categorized_prs = categorize_prs(prs)

local non_kongers_hash = get_non_konger_authors(api, commits)

print_report(categorized_prs, non_pr_commits, non_kongers_hash, to_ref)

