local router     = require "kong.portal.router"
local workspaces = require "kong.workspaces"

local valid_extension_list = {
  "txt", "md", "html", "json", "yaml", "yml",
}

local invalid_extension_list = {
  "txts", "masdd", "hfddtml", "jssfaon", "yaasml", "ymdfdl",
}


local function table_length(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end


describe("portal_router", function()
  describe("in-mem router", function()
    local snapshot

    before_each(function()
      snapshot = assert:snapshot()
    end)

    after_each(function()
      snapshot:revert()
    end)

    describe("add_route_by_content_file", function()
      it("can set files with 'content' prefix", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function()
              return nil
            end,
          }
        }

        local router = router.new(db)
        router.add_route_by_content_file({
          path = "content/index.md",
          contents = "title: hello"
        })
        router.add_route_by_content_file({
          path = "content/documentation/index.md",
          contents = "title: hello"
        })
        router.add_route_by_content_file({
          path = "content/a.md",
          contents = "title: hello"
        })
        router.add_route_by_content_file({
          path = "content/about/index.md",
          contents = "title: hello"
        })

        local ws_router = router.get_ws_router(router, {
          name = 'default'
        })

        assert.equal(4, table_length(ws_router))
      end)

      it("does not set files without 'content' prefix", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function()
              return nil
            end,
          }
        }

        local router = router.new(db)
        router.add_route_by_content_file({
          path = "/content/index.md",
          contents = "title: hello"
        })
        router.add_route_by_content_file({
          path = "dog/content/index.md",
          contents = "title: hello"
        })
        router.add_route_by_content_file({
          path = "themes/index.md",
          contents = "title: hello"
        })
        router.add_route_by_content_file({
          path = "contents/index.md",
          contents = "title: hello"
        })
        router.add_route_by_content_file({
          path = "asldkfjalskjdfasldkjfalksjfd",
          contents = "title: hello"
        })
        router.add_route_by_content_file({
          path = "$3@@@$%KDSK ksdfjkds",
          contents = "title: hello"
        })

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(0, table_length(ws_router))
      end)

      it("can set files with accepted extension types", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function()
              return nil
            end,
          }
        }

        local router = router.new(db)

        for i, v in ipairs(valid_extension_list) do
          router.add_route_by_content_file({
            path = "content/wut" .. tostring(i) .. "." .. v,
            contents = "title: hello"
          })

          local ws_router = router.get_ws_router({
            name = 'default'
          })

          assert.equal(i, table_length(ws_router))
        end
      end)

      it("cannot set files with invalid extension types", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function()
              return nil
            end,
          }
        }

        local router = router.new(db)

        for i, v in ipairs(invalid_extension_list) do
          router.add_route_by_content_file({
            path = "content/wut" .. tostring(i) .. "." .. v,
            contents = "title: hello"
          })

          local ws_router = router.get_ws_router({
            name = 'default'
          })

          assert.equal(0, table_length(ws_router))
        end
      end)

      it("overwrites lower priority content extensions", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function()
              return nil
            end,
          }
        }

        local router = router.new(db)

        for i, _ in ipairs(valid_extension_list) do
          local idx = #valid_extension_list - (i - 1)
          local v = valid_extension_list[idx]

          router.add_route_by_content_file({
            path = "content/index." .. v,
            contents = "title: hello"
          })

          local ws_router = router.get_ws_router({
            name = 'default'
          })

          assert.equal(1, table_length(ws_router))
          assert.equal('content/index.' .. v, ws_router["/"].path)
        end
      end)

      it("does not overwrite higher priority content extensions", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function()
              return nil
            end,
          }
        }

        local router = router.new(db)

        for i, v in ipairs(valid_extension_list) do
          router.add_route_by_content_file({
            path = "content/dog." .. v,
            contents = "title: hello"
          })

          local ws_router = router.get_ws_router({
            name = 'default'
          })

          assert.equal(1, table_length(ws_router))
          assert.equal('content/dog.txt', ws_router["/dog"].path)
        end

        for i, v in ipairs(valid_extension_list) do
          router.add_route_by_content_file({
            path = "content/dog/index." .. v,
            contents = "title: hello"
          })

          local ws_router = router.get_ws_router({
            name = 'default'
          })

          assert.equal(1, table_length(ws_router))
          assert.equal('content/dog.txt', ws_router["/dog"].path)
        end
      end)

      it("saves only relevant headmatter to route config", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function()
              return nil
            end,
          }
        }

        local file = {
          path = "content/index.html",
          contents =
          [[
            auth: true
            layout: index.html
            readable_by: humans
            url: dogs
          ]]
        }

        local router = router.new(db)

        router.add_route_by_content_file(file)

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(1, table_length(ws_router))
        assert.equal(true, ws_router["dogs"].auth)
        assert.equal('index.html', ws_router["dogs"].layout)
        assert.equal("humans", ws_router["dogs"].readable_by)
        assert.equal("dogs", ws_router["dogs"].url)
      end)

      it("saves only relevant headmatter to route config", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function()
              return nil
            end,
          }
        }

        local file = {
          path = "content/index.html",
          contents =
          [[
            auth: true
            layout: index.html
            readable_by: humans
            url: dogs
          ]]
        }

        local router = router.new(db)

        router.add_route_by_content_file(file)

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(1, table_length(ws_router))
        assert.equal(true, ws_router["dogs"].auth)
        assert.equal('index.html', ws_router["dogs"].layout)
        assert.equal("humans", ws_router["dogs"].readable_by)
        assert.equal("dogs", ws_router["dogs"].url)
      end)

      it("adds 'has_content' flag when user created content", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function()
              return nil
            end,
          }
        }

        local file = {
          path = "content/index.html",
          contents =
            [[
              auth: true
              title: yoooooo
              url: dogs
            ]]
        }

        local router = router.new(db)
        router.add_route_by_content_file(file)

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(1, table_length(ws_router))
        assert.equal(true, ws_router["dogs"].auth)
        assert.equal(true, ws_router["dogs"].has_content)
      end)

      it("cannot override route with existing 'url' decleration", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function()
              return nil
            end,
          }
        }

        local router = router.new(db)

        router.add_route_by_content_file({
          path = "content/index.html",
          contents =
            [[
              layout: locked.html
              url: /dogs
            ]]
        })

        router.add_route_by_content_file({
          path = "content/dogs.html",
          contents =
            [[
              layout: new.html
            ]]
        })

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(1, table_length(ws_router))
        assert.equal("locked.html", ws_router["/dogs"].layout)
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
      local db, router_files

      before_each(function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        router_files = {
          ["content/home/index.html"] = {
            path = "content/home/index.html",
            contents = [[name: index]]
          },
          ["content/dogs/cats/bats.md"] = {
            path = "content/dogs/cats/bats.md",
            contents = [[name: bats]]
          },
          ["content/docs/1.json"] = {
            path = "content/docs/1.json",
            contents = [[name: 1]]
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
        }

        db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function(self, path)
              return router_files[path]
            end,
          }
        }
      end)

      it("can set custom router", function()
        local router = router.new(db)
        local ws_router = router.get_ws_router(router, {
          name = 'default'
        })

        assert(ws_router.static)
        assert.equal("content/home/index.html", ws_router["*"].path)
        assert.equal("content/dogs/cats/bats.md", ws_router["dogs/cats"].path)
        assert.equal("content/docs/1.json", ws_router["documentation/doc1"].path)
      end)
    end)

    describe("get_route", function()
      local db, router_files

      before_each(function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        router_files = {
          ["content/home/index.html"] = {
            path = "content/home/index.html",
            contents = [[name: index]]
          },
          ["content/dogs/cats/bats.md"] = {
            path = "content/dogs/cats/bats.md",
            contents = [[name: bats]]
          },
          ["content/docs/1.json"] = {
            path = "content/docs/1.json",
            contents = [[name: 1]]
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
        }

        db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function(self, path)
              return router_files[path]
            end,
          }
        }
      end)

      it("can get wildcard content based off incoming routes", function()
        local router = router.new(db)
        local content1 = router.get("a/b/c")
        local content2 = router.get("dogs/cats/bath")
        local content3 = router.get("whatever")

        assert.equal("content/home/index.html", content1.path)
        assert.equal("content/home/index.html", content2.path)
        assert.equal("content/home/index.html", content3.path)
      end)

      it("can grab explicit content before wildcard", function()
        local router = router.new(db)
        local content1 = router.get("/dogs/cats")
        local content2 = router.get("/documentation/doc1")

        assert.equal("content/dogs/cats/bats.md", content1.path)
        assert.equal("content/docs/1.json", content2.path)
      end)
    end)

    describe("add_route_by_content_file", function()
      local router_files, db

      before_each(function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        router_files = {
          ["content/home/index.html"] = {
            path = "content/home/index.html",
            contents = [[name: index]]
          },
          ["content/dogs/cats/bats.md"] = {
            path = "content/dogs/cats/bats.md",
            contents = [[name: bats]]
          },
          ["content/docs/1.json"] = {
            path = "content/docs/1.json",
            contents = [[name: 1]]
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
        }

        db = {
          files = {
            each = function()
              return pairs({})
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function(self, path)
              return router_files[path]
            end,
          }
        }
      end)

      it("does not overwrite routes when static router set", function()
        local router = router.new(db)

        router.add_route_by_content_file({
          path = "dog.html",
          contents = [[dog: cat]]
        })
        router.add_route_by_content_file({
          path = "content/docs/1.html",
          contents = [[dog: cat]]
        })

        local ws_router = router.get_ws_router(router, {
          name = 'default'
        })

        assert(ws_router.static)
        assert.equal("content/home/index.html", ws_router["*"].path)
        assert.equal("content/dogs/cats/bats.md", ws_router["dogs/cats"].path)
        assert.equal("content/docs/1.json", ws_router["documentation/doc1"].path)
        assert.equal(nil, ws_router["dog"])
      end)
    end)
  end)
end)
