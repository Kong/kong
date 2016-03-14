local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local utils = require "kong.tools.utils"

describe("Admin API", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/cluster/events/", function()
    local BASE_URL = spec_helper.API_URL.."/cluster/events"

    describe("POST", function()
      it("[SUCCESS] should post a new event", function()
        local _, status = http_client.post(BASE_URL, {}, {})
        assert.equal(200, status)
      end)
    end)

  end)

  describe("/cluster/", function()

    local BASE_URL = spec_helper.API_URL.."/cluster/"
    
    describe("GET", function()
      it("[SUCCESS] should get the list of members", function()
        os.execute("sleep 2") -- Let's wait for serf to register the node

        local response, status = http_client.get(BASE_URL, {}, {})
        assert.equal(200, status)
        local body = json.decode(response)
        assert.truthy(body)
        assert.equal(1, #body.data)
        assert.equal(1, body.total)

        local member = body.data[1]
        assert.equal(3, utils.table_size(member))
        assert.truthy(member.address)
        assert.truthy(member.name)
        assert.truthy(member.status)

        assert.equal("alive", member.status)
      end)
    end)
    
    describe("DELETE", function()

      setup(function()
        os.execute([[nohup serf agent -rpc-addr=127.0.0.1:20000 -bind=127.0.0.1:20001 -node=helloworld > serf.log 2>&1 & echo $! > serf.pid]])
        -- Wait for agent to start
        while (os.execute("cat serf.log | grep running > /dev/null") / 256 == 1) do
        -- Wait
        end
      end)

      teardown(function()
        os.execute("kill -9 $(cat serf.pid) && rm serf.pid && rm serf.log")
      end)

      it("[SUCCESS] should force-leave a node", function()
        -- Join node
        os.execute("serf join -rpc-addr=127.0.0.1:9101 127.0.0.1:20001 > /dev/null")

        os.execute("sleep 2") -- Let's wait for serf to register the node

        local response, status = http_client.get(BASE_URL, {}, {})
        assert.equal(200, status)
        local body = json.decode(response)
        assert.truthy(body)
        assert.equal(2, #body.data)
        assert.equal(2, body.total)
        for _, v in ipairs(body.data) do
           assert.equal("alive", v.status)
        end

        local _, status = http_client.delete(BASE_URL, {name="helloworld"}, {})
        assert.equal(200, status)
        os.execute("sleep 2") -- Let's wait for serf to propagate the event

        response, status = http_client.get(BASE_URL, {}, {})
        assert.equal(200, status)
        local body = json.decode(response)
        assert.truthy(body)
        assert.equal(2, #body.data)
        assert.equal(2, body.total)
        local not_alive
        for _, v in ipairs(body.data) do
          if v.name == "helloworld" then
            assert.equal("leaving", v.status)
            not_alive = true
          end
        end
        assert.truthy(not_alive)
      end)
    end)

  end)
end)