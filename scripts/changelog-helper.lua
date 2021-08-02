#!/usr/bin/env resty
setmetatable(_G, nil)

local cjson = require "cjson"
local http = require "resty.http"

local USAGE = [[
  Usage:

  scripts/changelog-helper.lua <tag_from> <tag_to> <token>

  Example:

  scripts/changelog-helper.lua 2.4.1 master $GITHUB_TOKEN

  For the Github token, visit https://github.com/settings/tokens . It only needs "repo" scopes, without security_events.

  ** NOTE: Github limits the number of commits to compare to 250. If the diff is bigger, you will get an error, and will have to do the changelog manually **
]]

local fmt = string.format

local new_github_api = function(github_token)
  local get = function(path)
    local httpc = assert(http.new())
    httpc:set_timeout(10000)

    local res = assert(httpc:request_uri(
      fmt("https://api.github.com%s", path), {
        method = "GET",
        ssl_verify = false,
        headers = {
          ["Authorization"] = fmt("token %s", github_token),
          -- needed to get prs associated to sha (/repos/kong/kong/commits/%s/pulls):
          ["Accept"] = "application/vnd.github.groot-preview+json",
        }
      }
    ))
    local body = res.body
    if body and body ~= "" then
      body = cjson.decode(body)
    end
    return body, res.status
  end

  return { get = get }
end


local function get_comparison_commits(api, tag_from, tag_to)
  print("\n\nGetting comparison commits")
  local compare_res = api.get(fmt("/repos/kong/kong/compare/%s...%s", tag_from, tag_to))

  if #compare_res.commits >= 250 then
    error("250 commits or more found on compare. Github only shows 250 on its compare query, so the comparison likely is missing data. Aborting in order to not produce incomplete results")
  end

  return compare_res.commits
end


local function get_prs_from_comparison_commits(api, commits)
  local prs = {}

  print("\n\nGetting PRs associated to commits in main comparison")
  local prs_res, pr, last_pr_number
  for i, commit in ipairs(commits) do
    prs_res = api.get(fmt("/repos/kong/kong/commits/%s/pulls", commit.sha))
    pr = prs_res[1] -- FIXME perhaps find a more appropiate one using tag_to ?

    if type(pr) == "table" then
      if not prs[pr.number] then
        prs[pr.number] = pr
      end
      pr.commits = pr.commits or {}
      pr.commits[#pr.commits + 1] = commit
      if last_pr_number ~= pr.number then
        io.stdout:write(" #", pr.number)
      else
        io.stdout:write(".")
      end
      io.stdout:flush()
      last_pr_number = pr.number
    end

  end

  return prs
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
    local _, status = api.get(fmt("/orgs/kong/members/%s", login))
    if status ~= 302 then
      non_kongers[login] = true
      io.stdout:write(login)
      io.stdout:flush()
    end
  end

  return non_kongers
end


local function extract_type_and_scope_and_title(str)
  local typ, scope, title = string.match(str, "^([^%(]+)%(([^%)]+)%) (.+)$")
  return typ, scope, title
end


local function categorize_prs(prs)
  print("\n\nCategorizing PRs")
  local categorized_prs = {}
  local commits
  for pr_number,pr in pairs(prs) do
    commits = {}
    for _,c in ipairs(pr.commits) do
      commits[#commits + 1] = {
        author = c.author and c.author.login or "unknown",
        message = c.commit.message,
      }
    end

    local typ, scope, title = extract_type_and_scope_and_title(pr.title)
    -- when pr title does not follow the "type(scope) title" format, use the last commit on the PR to extract type & scope
    if not typ then
      title = pr.title
      typ, scope = extract_type_and_scope_and_title(commits[#commits].message)
      if not typ then
        typ, scope = "unknown", "unknown"
      end
    end

    categorized_prs[pr_number] = { title = title, typ = typ, scope = scope, url = pr.html_url, description = pr.body, commits = commits }
  end

  return categorized_prs
end


local function print_categorized_prs(categorized_prs, non_kongers_hash)
  local pr_numbers = {}
  for pr_number in pairs(categorized_prs) do
    pr_numbers[#pr_numbers + 1] = pr_number
  end
  table.sort(pr_numbers)

  local pr
  for _,pr_number in ipairs(pr_numbers) do
    pr = categorized_prs[pr_number]
    print(require("inspect")(pr))
  end
end



-----------------------

local tag_from, tag_to, github_token = arg[1], arg[2], arg[3]

if not tag_from or not tag_to or not github_token then
  print(USAGE)
  os.exit(0)
end

local api = new_github_api(github_token)

local commits = get_comparison_commits(api, tag_from, tag_to)

local prs = get_prs_from_comparison_commits(api, commits)

local categorized_prs = categorize_prs(prs)

local non_kongers_hash = get_non_konger_authors(api, commits)

print_categorized_prs(categorized_prs, non_kongers_hash)

