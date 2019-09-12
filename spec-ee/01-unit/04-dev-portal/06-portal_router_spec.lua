local constants  = require "kong.constants"
local router     = require "kong.portal.router"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"

local valid_extension_list = constants.PORTAL_RENDERER.EXTENSION_LIST
local invalid_extension_list = {
  "txts", "masdd", "hfddtml", "jssfaon", "yaasml", "ymdfdl",
}


local function table_length(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end


describe("portal_router", function()
  describe("build", function()
    local db, router_files

    before_each(function()
      stub(workspaces, "get_workspace").returns({
        name = "default",
        config = {},
      })

      router_files = {
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
      }

      db = {
        files = {
          each = function()
            local files = {}
            for k, v in pairs(router_files) do
              files[v] = ""
            end
            return pairs(files)
          end,
          select_all = function()
            return {}
          end,
          select_by_path = function(self, path)
            return router_files[path]
          end,
        }
      }

      singletons.db = db
    end)

    it("can set collection router", function()
      local router = router.new(db)
      local ws_router = router.get_ws_router(router, {
        name = 'default'
      })

      assert.equal("content/_posts/sick.txt", ws_router.collection["/blog/posts/sick"].path_meta.full_path)
      assert.equal("content/_posts/rad.txt", ws_router.collection["/blog/posts/rad"].path_meta.full_path)
      assert.equal("content/_posts/cool.txt", ws_router.collection["/blog/posts/cool"].path_meta.full_path)
      assert.is_nil(ws_router.collection["blog/posts/gnarly"])
    end)

    it("can set explicit router", function()
      local router = router.new(db)
      local ws_router = router.get_ws_router(router, {
        name = 'default'
      })

      assert.equal("content/_posts/gnarly.txt", ws_router.explicit["/gnarly"].path_meta.full_path)
      assert.equal("content/docs/2.json", ws_router.explicit["/docs_r_kewl"].path_meta.full_path)
    end)

    it("can set content router", function()
      local router = router.new(db)
      local ws_router = router.get_ws_router(router, {
        name = 'default'
      })

      assert.equal("content/docs/1.json", ws_router.content["/docs/1"].path_meta.full_path)
      assert.equal("content/dogs/cats/bats.md", ws_router.content["/dogs/cats/bats"].path_meta.full_path)
      assert.equal("content/home/index.html", ws_router.content["/home"].path_meta.full_path)
    end)
  end)

  describe("add_route_by_content_file", function()
    describe("'content' router", function()
      it("can set 'content' routes", function()
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

        singletons.db = db

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

        assert.equal(4, table_length(ws_router.content))
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

        singletons.db = db

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

        assert.equal(0, table_length(ws_router.content))
        assert.equal(0, table_length(ws_router.collection))
        assert.equal(0, table_length(ws_router.explicit))
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

          assert.equal(i, table_length(ws_router.content))
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

          assert.equal(0, table_length(ws_router.content))
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

          assert.equal(1, table_length(ws_router.content))
          assert.equal('content/index.' .. v, ws_router.content["/"].path_meta.full_path)
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

          assert.equal(1, table_length(ws_router.content))
          assert.equal('content/dog.txt', ws_router.content["/dog"].path_meta.full_path)
        end

        for i, v in ipairs(valid_extension_list) do
          router.add_route_by_content_file({
            path = "content/dog/index." .. v,
            contents = "title: hello"
          })

          local ws_router = router.get_ws_router({
            name = 'default'
          })

          assert.equal(1, table_length(ws_router.content))
          assert.equal('content/dog.txt', ws_router.content["/dog"].path_meta.full_path)
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
          path = "content/home/index.html",
          contents =
          [[
            ---
            readable_by: "*"
            layout: index.html
            title: I like turtles
            ---
          ]]
        }

        local router = router.new(db)

        router.add_route_by_content_file(file)

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(1, table_length(ws_router.content))
        assert.equal("*", ws_router.content["/home"].headmatter.readable_by)
        assert.equal('index.html', ws_router.content["/home"].layout)
        assert.is_nil(ws_router.content["/home"].title)
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
          path = "content/home/index.html",
          contents =
            [[
              ---
              readable_by: "*"
              title: yoooooo
              ---
            ]]
        }

        local router = router.new(db)
        router.add_route_by_content_file(file)

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(1, table_length(ws_router.content))
        assert.equal("*", ws_router.content["/home"].headmatter.readable_by)
      end)
    end)

    describe("'explicit' router", function()
      it("can set routes", function()
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

        singletons.db = db

        local router = router.new(db)
        router.add_route_by_content_file({
          path = "content/index.md",
          contents = [[
            ---
            route: /1
            ---
          ]]
        })
        router.add_route_by_content_file({
          path = "content/documentation/index.md",
          contents = [[
            ---
            route: /2
            ---
          ]]
        })
        router.add_route_by_content_file({
          path = "content/a.md",
          contents = [[
            ---
            route: /3
            ---
          ]]
        })
        router.add_route_by_content_file({
          path = "content/about/index.md",
          contents = [[
            ---
            route: /4
            ---
          ]]
        })

        local ws_router = router.get_ws_router(router, {
          name = 'default'
        })

        assert.equal(4, table_length(ws_router.explicit))
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
            contents = "---" .. "route: /dog" .. tostring(i) .. "---"
          })

          local ws_router = router.get_ws_router({
            name = 'default'
          })

          assert.equal(i, table_length(ws_router.explicit))
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
            contents = "---route: wut" .. tostring(i) .. "---"
          })

          local ws_router = router.get_ws_router({
            name = 'default'
          })

          assert.equal(0, table_length(ws_router.explicit))
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
          path = "content/home/index.html",
          contents =
          [[
            ---
            layout: index.html
            readable_by: humans
            title: I like turtles
            route: /doggo
            ---
          ]]
        }

        local router = router.new(db)

        router.add_route_by_content_file(file)

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(1, table_length(ws_router.explicit))
        assert.equal('index.html', ws_router.explicit["/doggo"].layout)
        assert.equal("humans", ws_router.explicit["/doggo"].headmatter.readable_by)
        assert.is_nil(ws_router.explicit["/doggo"].title)
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
          path = "content/home/index.html",
          contents =
            [[
              ---
              title: yoooooo
              route: /doggo
              ---
            ]]
        }

        local router = router.new(db)
        router.add_route_by_content_file(file)

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(1, table_length(ws_router.explicit))
      end)
    end)

    describe("'collection' router", function()
      local db

      lazy_setup(function()
        local router_files = {
          ["portal.conf.yaml"] = {
            path = "portal.conf.yaml",
            contents = [[
              collections:
                posts:
                  output: true
                  route: /blog/:collection/:name
            ]]
          }
        }

        db = {
          files = {
            each = function()
              local files = {}
              for k, v in pairs(router_files) do
                files[v] = ""
              end
              return pairs(files)
            end,
            select_all = function()
              return {}
            end,
            select_by_path = function(self, path)
              return router_files[path]
            end,
          }
        }

        singletons.db = db
      end)

      it("can set routes", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local router = router.new(db)
        router.add_route_by_content_file({
          path = "content/_posts/dog.md",
          contents = "---title: dog---"
        })
        router.add_route_by_content_file({
          path = "content/_posts/cat.md",
          contents = "---title: cat---"
        })
        router.add_route_by_content_file({
          path = "content/_posts/bat.md",
          contents = "---title: bat---"
        })

        local ws_router = router.get_ws_router(router, {
          name = 'default'
        })

        assert.equal(3, table_length(ws_router.collection))
        assert.equal("content/_posts/dog.md", ws_router.collection["/blog/posts/dog"].path_meta.full_path)
        assert.equal("content/_posts/cat.md", ws_router.collection["/blog/posts/cat"].path_meta.full_path)
        assert.equal("content/_posts/bat.md", ws_router.collection["/blog/posts/bat"].path_meta.full_path)
      end)

      it("can set files with accepted extension types", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })
        local router = router.new(db)

        for i, v in ipairs(valid_extension_list) do
          router.add_route_by_content_file({
            path = "content/_posts/dog" .. tostring(i) .. "." .. v,
            contents = "title: dog" .. tostring(i)
          })

          local ws_router = router.get_ws_router({
            name = 'default'
          })

          assert.equal(i, table_length(ws_router.collection))
        end
      end)

      it("cannot set files with invalid extension types", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local router = router.new(db)

        for i, v in ipairs(invalid_extension_list) do
          router.add_route_by_content_file({
            path = "content/_posts/dog" .. tostring(i) .. "." .. v,
            contents = "title: dog" .. tostring(i)
          })

          local ws_router = router.get_ws_router({
            name = 'default'
          })

          assert.equal(0, table_length(ws_router.collection))
        end
      end)

      it("saves only relevant headmatter to route config", function()
        stub(workspaces, "get_workspace").returns({
          name = "default",
          config = {},
        })

        local file = {
          path = "content/_posts/dog.html",
          contents =
          [[
            ---
            layout: index.html
            readable_by: humans
            title: I like turtles
            ---
          ]]
        }

        local router = router.new(db)

        router.add_route_by_content_file(file)

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(1, table_length(ws_router.collection))
        assert.equal('index.html', ws_router.collection["/blog/posts/dog"].layout)
        assert.equal("humans", ws_router.collection["/blog/posts/dog"].headmatter.readable_by)
        -- assert.is_nil(ws_router.collection["/blog/posts/dog"].title)
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
          path = "content/_posts/dog.html",
          contents =
            [[
              ---
              title: yoooooo
              ---
            ]]
        }

        local router = router.new(db)
        router.add_route_by_content_file(file)

        local ws_router = router.get_ws_router({
          name = 'default'
        })

        assert.equal(1, table_length(ws_router.collection))
        -- assert.equal(true, ws_router.collection["/blog/posts/dog"].has_content)
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

        singletons.db = db
      end)

      it("can set custom router", function()
        local router = router.new(db)
        local ws_router = router.get_ws_router(router, {
          name = 'default'
        })

        assert.equal("content/home/index.html", ws_router.custom["*"].path_meta.full_path)
        assert.equal("content/dogs/cats/bats.md", ws_router.custom["dogs/cats"].path_meta.full_path)
        assert.equal("content/docs/1.json", ws_router.custom["documentation/doc1"].path_meta.full_path)
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

        singletons.db = db
      end)

      it("can get wildcard content based off incoming routes", function()
        local router = router.new(db)
        local content1 = router.get("a/b/c")
        local content2 = router.get("dogs/cats/bath")
        local content3 = router.get("whatever")

        assert.equal("content/home/index.html", content1.path_meta.full_path)
        assert.equal("content/home/index.html", content2.path_meta.full_path)
        assert.equal("content/home/index.html", content3.path_meta.full_path)
      end)

      it("can grab explicit content before wildcard", function()
        local router = router.new(db)
        local content1 = router.get("/dogs/cats")
        local content2 = router.get("/documentation/doc1")

        assert.equal("content/dogs/cats/bats.md", content1.path_meta.full_path)
        assert.equal("content/docs/1.json", content2.path_meta.full_path)
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
          contents = [[
            ---
            dog: cat
            ---
          ]]
        })
        router.add_route_by_content_file({
          path = "content/docs/1.html",
          contents = [[
            ---
            dog: cat
            ---
          ]]
        })

        local ws_router = router.get_ws_router(router, {
          name = 'default'
        })

        assert.equal("content/home/index.html", ws_router.custom["/*"].path_meta.full_path)
        assert.equal("content/dogs/cats/bats.md", ws_router.custom["/dogs/cats"].path_meta.full_path)
        assert.equal("content/docs/1.json", ws_router.custom["/documentation/doc1"].path_meta.full_path)
        assert.equal(nil, ws_router["dog"])
      end)
    end)
  end)
end)
