local constants  = require "kong.constants"
local router     = require "kong.portal.router"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"

local valid_extension_list = constants.PORTAL_RENDERER.EXTENSION_LIST


local function table_length(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end


local function build_router(db, delay)
  if not delay then
    delay = 0.1
  end

  local router = router.new(db)
  router.get('/')
  ngx.sleep(delay)

  return router
end


local function populate_files(router_files)
  local _files = router_files
  singletons.db = {
    files = {
      each = function()
        local files = {}
        for k, v in pairs(_files) do
          files[v] = ""
        end
        return pairs(files)
      end,
      select_all = function()
        return {}
      end,
      select_by_path = function(self, path)
        return _files[path]
      end,
    }
  }
end


describe("portal_router", function()
  describe("build", function()
    before_each(function()
      stub(workspaces, "get_workspace").returns({
        name = "default",
        config = {},
      })

      populate_files({
        ["content/home/index.html"] = {
          path = "content/home/index.html",
          contents = [[
            ---
            name: index
            ---
          ]]
        },
        ["content/dogs/cats/bats.md"] = {
          path = "content/dogs/cats/bats.md",
          contents = [[
            ---
            name: bats
            ---
          ]]
        },
        ["content/docs/1.json"] = {
          path = "content/docs/1.json",
          contents = [[
            ---
            name: 1
            ---
          ]]
        },
        ["content/_posts/sick.txt"] = {
          path = "content/_posts/sick.txt",
          contents = [[
            ---
            name: index
            ---
          ]]
        },
        ["content/_posts/rad.txt"] = {
          path = "content/_posts/rad.txt",
          contents = [[
            ---
            name: index
            ---
          ]]
        },
        ["content/_posts/cool.txt"] = {
          path = "content/_posts/cool.txt",
          contents = [[
            ---
            name: index
            ---
          ]]
        },
        ["content/_posts/gnarly.txt"] = {
          path = "content/_posts/gnarly.txt",
          contents = [[
            ---
            route: /gnarly
            ---
          ]]
        },
        ["content/docs/2.json"] = {
          path = "content/docs/2.json",
          contents = [[
            ---
            route: /docs_r_kewl
            ---
          ]]
        },
        ["portal.conf.yaml"] = {
          path = "portal.conf.yaml",
          contents = [[
            collections:
              posts:
                output: true
                route: /blog/:collection/:name
          ]]
        },
        ["specs/spec1.json"] = {
          path = "specs/spec1.json",
          contents = [[]]
        },
        ["specs/spec2.json"] = {
          path = "specs/spec2.json",
          contents = [[]]
        },
      })
    end)

    it("can set collection router", function()
      local router = build_router(singletons.db)
      local router_state = router.introspect()
      local ws_router = router_state.router.default

      assert.equal("content/_posts/sick.txt", ws_router.collection["/blog/posts/sick"].path_meta.full_path)
      assert.equal("content/_posts/rad.txt", ws_router.collection["/blog/posts/rad"].path_meta.full_path)
      assert.equal("content/_posts/cool.txt", ws_router.collection["/blog/posts/cool"].path_meta.full_path)
      assert.is_nil(ws_router.collection["blog/posts/gnarly"])
    end)

    it("can set explicit router", function()
      local router = build_router(singletons.db)
      local router_state = router.introspect()
      local ws_router = router_state.router.default

      assert.equal("content/_posts/gnarly.txt", ws_router.explicit["/gnarly"].path_meta.full_path)
      assert.equal("content/docs/2.json", ws_router.explicit["/docs_r_kewl"].path_meta.full_path)
    end)

    it("can set content router", function()
      local router = build_router(singletons.db)
      local router_state = router.introspect()
      local ws_router = router_state.router.default

      assert.equal("content/docs/1.json", ws_router.content["/docs/1"].path_meta.full_path)
      assert.equal("content/dogs/cats/bats.md", ws_router.content["/dogs/cats/bats"].path_meta.full_path)
      assert.equal("content/home/index.html", ws_router.content["/home"].path_meta.full_path)
    end)
  end)

  describe("build", function()
    before_each(function()
      stub(workspaces, "get_workspace").returns({
        name = "default",
        config = {},
      })
    end)

    describe("up to date router", function()
      it("files with higher priority take route precedence", function()
        local files = {}
        local extensions = valid_extension_list
        for i, _ in ipairs(extensions) do
          local ext = extensions[#extensions - i + 1]
          local filename = "content/home/index." .. ext
          files[filename] = {
            path = filename,
            contents = [[
              ---
              name: index
              ---
            ]]
          }

          populate_files(files)
          local router = build_router(singletons.db)
          local router_state = router.introspect()
          local ws_router = router_state.router.default
          assert.equal(filename, ws_router.content["/home"].path_meta.full_path)
        end
      end)

      it("can build collections", function()
        local files = {
          ["content/home/index.txt"] = {
            path = "content/home/index.txt",
            contents = [[
              ---
              name: index
              ---
            ]]
          },
          ["portal.conf.yaml"] = {
            path = "portal.conf.yaml",
            contents = [[
              collections:
                guides:
                  output: true
                  route: /:collection/:name
            ]]
          },
        }

        for i=1, 100 do
          local filename = "content/_guides/" .. i .. ".txt"
          files[filename] = {
            path = filename,
            contents = [[
              ---
              name: guide
              ---
            ]]
          }
        end

        populate_files(files)
        local router = build_router(singletons.db)
        local router_state = router.introspect()
        local ws_router = router_state.router.default

        assert.equal("content/home/index.txt", ws_router.content["/home"].path_meta.full_path)
        assert.equal(100, table_length(ws_router.collection))
        for i=1, 100 do
          assert.equal("content/_guides/" .. i .. ".txt", ws_router.collection["/guides/" .. i].path_meta.full_path)
        end
      end)
    end)
  end)

  describe("router.conf.yaml router", function()
    local snapshot

    before_each(function()
      snapshot = assert:snapshot()
    end)

    after_each(function()
      snapshot:revert()
    end)

    describe("build custom router", function()
      before_each(function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        populate_files({
          ["content/home/index.html"] = {
            path = "content/home/index.html",
            contents = [[
              ---
              name: index
              ---
            ]]
          },
          ["content/dogs/cats/bats.md"] = {
            path = "content/dogs/cats/bats.md",
            contents = [[
              ---
              name: bats
              ---
            ]]
          },
          ["content/docs/1.json"] = {
            path = "content/docs/1.json",
            contents = [[
              ---
              name: 1
              ---
            ]]
          },
          ["router.conf.yaml"] = {
            path = "router.conf.yaml",
            contents =
              [[
                "*": "content/home/index.html"
                "dogs/cats": "content/dogs/cats/bats.md"
                "documentation/doc1": "content/docs/1.json"
              ]]
          },
        })
      end)

      it("can set custom router", function()
        local router = build_router(singletons.db)
        local router_state = router.introspect()
        local ws_router = router_state.router.default

        assert.equal("content/home/index.html", ws_router.custom["*"].path_meta.full_path)
        assert.equal("content/dogs/cats/bats.md", ws_router.custom["dogs/cats"].path_meta.full_path)
        assert.equal("content/docs/1.json", ws_router.custom["documentation/doc1"].path_meta.full_path)
      end)
    end)

    describe("get_route", function()
      before_each(function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        populate_files({
          ["content/home/index.html"] = {
            path = "content/home/index.html",
            contents = [[
              ---
              name: index
              ---
            ]]
          },
          ["content/dogs/cats/bats.md"] = {
            path = "content/dogs/cats/bats.md",
            contents = [[
              ---
              name: bats
              ---
            ]]
          },
          ["content/docs/1.json"] = {
            path = "content/docs/1.json",
            contents = [[
              ---
              name: 1
              ---
            ]]
          },
          ["router.conf.yaml"] = {
            path = "router.conf.yaml",
            contents =
              [[
                "/*": "content/home/index.html"
                "/dogs/cats": "content/dogs/cats/bats.md"
                "/documentation/doc1": "content/docs/1.json"
              ]]
          },
        })
      end)

      it("can get wildcard content based off incoming routes", function()
        local router = build_router(singletons.db)
        local content1 = router.get("a/b/c")
        local content2 = router.get("dogs/cats/bath")
        local content3 = router.get("whatever")

        assert.equal("content/home/index.html", content1.path_meta.full_path)
        assert.equal("content/home/index.html", content2.path_meta.full_path)
        assert.equal("content/home/index.html", content3.path_meta.full_path)
      end)

      it("can grab explicit content before wildcard", function()
        local router = build_router(singletons.db)
        local content1 = router.get("/dogs/cats")
        local content2 = router.get("/documentation/doc1")

        assert.equal("content/dogs/cats/bats.md", content1.path_meta.full_path)
        assert.equal("content/docs/1.json", content2.path_meta.full_path)
      end)
    end)
  end)
end)
