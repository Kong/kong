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


-----------------------

local tag_from, tag_to, github_token = arg[1], arg[2], arg[3]

if not tag_from or not tag_to or not github_token then
  print(USAGE)
  os.exit(0)
end

local api = new_github_api(github_token)

print("Getting main comparison")
local compare_res = api.get(fmt("/repos/kong/kong/compare/%s...%s", tag_from, tag_to))

if #compare_res.commits >= 250 then
  error("250 commits found on compare. Github only shows 250 on its compare query, so this likely is missing data")
end

local authors = {}
local prs = {}
local pr_numbers = {}

print("Getting PRs for comparison")
local prs_res, pr, last_pr_number
for i, commit in ipairs(compare_res.commits) do
  prs_res = api.get(fmt("/repos/kong/kong/commits/%s/pulls", commit.sha))
  pr = prs_res[1] -- FIXME perhaps find a more appropiate one using tag_to ?

  if type(pr) == "table" then
    if not prs[pr.number] then
      prs[pr.number] = pr
      pr_numbers[#pr_numbers + 1] = pr.number
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

  if type(commit.author) == "table" then -- can be null
    authors[commit.author.login] = commit.author
  end
end

print("\n\nFinding non-konger authors")
for login, author in pairs(authors) do
  local _, status = api.get(fmt("/orgs/kong/members/%s", login))
  if status == 302 then
    author.konger = true
  else
    author.konger = false
    io.stdout:write(login)
    io.stdout:flush()
  end
end


table.sort(pr_numbers)
local pr
for _,pr_number in ipairs(pr_numbers) do
  pr = prs[pr_number]
  local commits = {}
  for _,c in ipairs(pr.commits) do
    commits[#commits + 1] = {
      author = c.author and c.author.login or "unknown",
      message = c.commit.message,
    }
  end
  print(require("inspect")({ title = pr.title, url = pr.html_url, description = pr.body, commits = commits }))
end


