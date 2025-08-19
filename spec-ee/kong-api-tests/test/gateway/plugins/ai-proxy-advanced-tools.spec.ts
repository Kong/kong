import {
  expect,
  createGatewayService,
  createRouteForService,
  clearAllKongResources,
  getBasePath,
  isGateway,
  Environment,
  logResponse,
  waitForConfigRebuild,
  vars,
  evaluateAIResponseStructure,
  retryAIRequest,
} from '@support'
import axios from 'axios';

// This test verify the tool call functionality of the AI Proxy advanced plugin.
describe('Gateway Plugins: AI Proxy Advanced Tool Call Test', function () {
  const providers = [
    {
      name: 'openai',
      variant: 'openai',
      model: 'gpt-4',
      options: null,
      auth_header: 'Authorization',
      auth_key: `Bearer ${vars.ai_providers.OPENAI_API_KEY}`,
    },

    {
      name: 'anthropic',
      variant: 'anthropic',
      model: 'claude-3-5-haiku-20241022',
      options: {
        "anthropic_version": "2023-06-01",
        "max_tokens": 256
      },
      auth_header: 'x-api-key',
      auth_key: `${vars.ai_providers.ANTHROPIC_API_KEY}`,
    },

    //GCP vertex via API
    {
      name: 'gemini',
      variant: 'vertex',  //enterprise use (Vertex AI)
      model: 'gemini-2.0-flash',
      options: {
        "gemini": {
          "location_id": "us-central1",
          "api_endpoint": "us-central1-aiplatform.googleapis.com",
          "project_id": "gcp-sdet-test"
        }
      },
      auth_header: null,
      auth_key: null,
      gcp_use_service_account: true,
      gcp_service_account_json: `${vars.ai_providers.VERTEX_API_KEY}`
    },

    //Google gemini public use via API
    {
      name: 'gemini',
      variant: 'gemini',  // Gemini public use (Gemini public AI)
      model: 'gemini-2.0-flash',
      options: null,
      auth_header: null,
      auth_key: null,
      param_name: 'key',
      param_location: 'query',
      param_value: `${vars.ai_providers.GEMINI_API_KEY}`
    },

    {
      name: 'azure',
      variant: 'azure',
      model: 'gpt-4.1-mini',
      options: {
        "azure_instance": "ai-gw-sdet-e2e-test",
        "azure_deployment_id": "gpt-4.1-mini",
        "max_tokens": 256,
        "azure_api_version": "2024-10-21"
      },
      auth_header: 'api-key',
      auth_key: `${vars.ai_providers.AZUREAI_API_KEY}`
    },

    {
      name: 'bedrock',
      variant: 'bedrock',
      model: 'anthropic.claude-3-haiku-20240307-v1:0',
      options: {
        "bedrock": {
          "aws_region": "us-east-1",
        }
      },
      auth_header: null,
      auth_key: null,
      aws_access_key_id: `${vars.aws.AWS_ACCESS_KEY_ID}`,
      aws_secret_access_key: `${vars.aws.AWS_SECRET_ACCESS_KEY}`
    }
  ]

  const adminUrl = getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })
  const proxyUrl = getBasePath({
    environment: isGateway() ? Environment.gateway.proxy : undefined,
  })
  const path = '/ai_proxy_test'

  let serviceId: string
  let pluginId: string

  before(async function () {
    // add header to every axios request in this suite
    axios.defaults.headers.common['Accept-Encoding'] = 'application/json,gzip,deflate'

    //create a service and route for use with plugin
    const service = await createGatewayService('ai-test-service')
    serviceId = service.id
    await createRouteForService(serviceId, [path])

    await waitForConfigRebuild()
  })

  providers.forEach((provider) => {
    const pluginPayload = {
      name: 'ai-proxy-advanced',
      service: { id: serviceId },
      config: {
        llm_format: "openai",
        targets: [{
          model: {
            name: provider.model,
            provider: provider.name,
            options: provider.options || {}
          },
          auth: {
            param_name: provider.param_name || null,
            param_value: provider.param_value || null,
            param_location: provider.param_location || null,
            allow_override: false,
            azure_client_id: null,
            azure_client_secret: null,
            azure_tenant_id: null,
            azure_use_managed_identity: false,
            aws_access_key_id: provider.aws_access_key_id || null,
            aws_secret_access_key: provider.aws_secret_access_key || null,
            header_name: provider.auth_header,
            header_value: provider.auth_key,
            gcp_use_service_account: provider.gcp_use_service_account || false,
            gcp_service_account_json: provider.gcp_service_account_json || null
          },
          route_type: 'llm/v1/chat',
        }],
        balancer: {
          algorithm: 'round-robin',
        },
        model_name_header: true
      }
    }

    it(`should create AI proxy using ${provider.variant} provider and chat model ${provider.model} model`, async function () {
      // setting service id to plugin payload as we can now access the serviceId inside it (test) scope
      pluginPayload.service.id = serviceId

      const resp = await axios({
        method: 'post',
        url: `${adminUrl}/services/${serviceId}/plugins`,
        data: pluginPayload,
        validateStatus: null
      })

      logResponse(resp)
      pluginId = resp.data.id

      expect(resp.status, 'Status should be 201').to.equal(201)
      await waitForConfigRebuild()
    })

    it(`should be able to send properly formatted chat message with tool call info to ${provider.variant} provider and chat model ${provider.model} via route`, async function () {
      if (provider.variant === 'vertex' || provider.variant === 'gemini') {
        this.skip(); // The tool call feature doesn't work well for gemini at the moment.
        // TODO: investigate if this is a bug or a limitation of the provider
      }

      const makeRequest = () => axios({
        method: 'post',
        url: `${proxyUrl}${path}`,
        data: {
          messages: [{
            'role': 'user',
            'content': 'What is the weather like in Boston today?'
          }],
          tools: [
            {
              type: "function",
              function: {
                name: "get_current_weather",
                description: "Get the current weather in a given location",
                parameters: {
                  type: "object",
                  properties: {
                    location: {
                      type: "string",
                      description: "The city and state, e.g. San Francisco, CA",
                    },
                    unit: {
                      type: "string",
                      enum: ["celsius", "fahrenheit"],
                    },
                  },
                  required: ["location"],
                },
              },
            },
          ],
          tool_choice: "auto",
        },
        validateStatus: null
      });

      await retryAIRequest(
        makeRequest,
        (resp) => {
          logResponse(resp)
          evaluateAIResponseStructure(resp, provider.variant, provider.model)
        },
        provider.variant
      );
    })

    it('should delete AI proxy', async function () {
      const resp = await axios({
        method: 'delete',
        url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`
      })
      logResponse(resp)
      expect(resp.status, 'Should have 204 status code').to.equal(204)
    })
  })

  after(async function () {
    await clearAllKongResources();
  });

});
