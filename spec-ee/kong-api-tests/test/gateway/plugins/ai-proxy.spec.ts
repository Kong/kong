import axios from 'axios';
import FormData from 'form-data';
import fs from 'fs';
import {
  expect,
  createGatewayService,
  createRouteForService,
  clearAllKongResources,
  getKongContainerName,
  isGwHybrid,
  getBasePath,
  isGateway,
  Environment,
  logResponse,
  waitForConfigRebuild,
  vars,
  createPlugin,
  patchRoute,
  createFileInDockerContainer,
  checkFileExistsInDockerContainer,
  copyFileFromDockerContainer,
  deleteFileFromDockerContainer,
  getTargetFileContent,
  postNegative,
  eventually,
  deleteTargetFile,
  createPolly,
  evaluateAIResponseStructure,
  retryAIRequest,
} from '@support'

describe('Gateway Plugins: AI Proxy', function () {
  this.timeout(75000); // 75 seconds for all tests in this suite
  //providers do not support preserve will skip route_type 'preserve' tests
  const excludedCompletionVariants = new Set(['gemini', 'vertex', 'azure', 'bedrock']);
  const providers = [
    {
      name: 'openai',
      variant: 'openai',
      chat: {
        model: 'gpt-4',
        options: null
      },
      completions: {
        model: 'gpt-3.5-turbo-instruct',
        options: null
      },
      image: {
        model: 'gpt-4o-mini',
        options: null
      },
      image_generation: {
        model: 'dall-e-3',
        options: null
      },
      audio: {
        model: 'whisper-1',
        options: null
      },
      auth_header: 'Authorization',
      auth_key: `Bearer ${vars.ai_providers.OPENAI_API_KEY}`,
    },
    //mistral via API does not do audio transcription or image generation
    {
      name: 'mistral',
      variant: 'mistral',
      chat: {
        model: 'mistral-large-latest',
        options: {
          mistral_format: 'openai',
          upstream_url: 'https://api.mistral.ai/v1/chat/completions'
        }
      },
      completions: {
        model: 'codestral-latest',
        options: {
          mistral_format: 'openai',
          upstream_url: 'https://api.mistral.ai/v1/fim/completions'
        }
      },
      image: {
        model: 'pixtral-12b-2409',
        options: {
          mistral_format: 'openai',
          upstream_url: 'https://api.mistral.ai/v1/img/completions'
        }
      },
      image_generation: {
        model: null,
        options: null
      },
      audio: {
        model: null,
        options: null
      },
      auth_key: `Bearer ${vars.ai_providers.MISTRAL_API_KEY}`,
    },
    //anthropic via API does not do audio transcription or image generation or completion mode
    {
      name: 'anthropic',
      variant: 'anthropic',
      chat: {
        model: 'claude-3-5-haiku-20241022',
        options: {
          "anthropic_version": "2023-06-01",
          "max_tokens": 256
        }
      },
      completions: {
        model: null,
        options: null,
      },
      image: {
        model: null,
        options: null
      },
      image_generation: {
        model: null,
        options: null
      },
      audio: {
        model: null,
        options: null
      },
      auth_header: 'x-api-key',
      auth_key: `${vars.ai_providers.ANTHROPIC_API_KEY}`,
    },
    //GCP vertex via API does not do audio transcription or image generation or completion mode
    {
      name: 'gemini',
      variant: 'vertex',  //enterprise use (Vertex AI)
      chat: {
        model: 'gemini-2.0-flash',
        options: {
          "gemini": {
            "location_id": "us-central1",
            "api_endpoint": "us-central1-aiplatform.googleapis.com",
            "project_id": "gcp-sdet-test"
          }
        }
      },
      completions: {
        model: null,
        options: null
      },
      image: {
        model: null,
        options: null
      },
      image_generation: {
        model: null,
        options: null
      },
      audio: {
        model: null,
        options: null
      },
      auth_header: null,
      auth_key: null,
      gcp_use_service_account: true,
      gcp_service_account_json: `${vars.ai_providers.VERTEX_API_KEY}`
    },
    {
      name: 'gemini',
      variant: 'vertex',  //enterprise use (Vertex AI)
      chat: {
        model: 'meta-llama/Llama-3.1-8B-Instruct',
        options: {
          "upstream_url": "https://us-central1-aiplatform.googleapis.com/v1/projects/432057123508/locations/us-central1/endpoints/9006006284624855040/chat/completions"
        }
      },
      completions: {
        model: null,
        options: null
      },
      image: {
        model: null,
        options: null
      },
      image_generation: {
        model: null,
        options: null
      },
      audio: {
        model: null,
        options: null
      },
      auth_header: null,
      auth_key: null,
      gcp_use_service_account: true,
      gcp_service_account_json: `${vars.ai_providers.VERTEX_API_KEY}`
    },
    //Google gemini public use via API does not do audio transcription or image generation or completion mode
    {
      name: 'gemini',
      variant: 'gemini',  // Gemini public use (Gemini public AI)
      chat: {
        model: 'gemini-2.0-flash',
        options: null
      },
      completions: {
        model: null,
        options: null
      },
      image: {
        model: null,
        options: null
      },
      image_generation: {
        model: null,
        options: null
      },
      audio: {
        model: null,
        options: null
      },
      auth_header: null,
      auth_key: null,
      param_name: 'key',
      param_location: 'query',
      param_value: `${vars.ai_providers.GEMINI_API_KEY}`
    },
    //azure via API does not do audio transcription or image generation or completion mode
    {
      name: 'azure',
      variant: 'azure',
      chat: {
        model: 'gpt-4.1-mini',
        options: {
          "azure_instance": "ai-gw-sdet-e2e-test",
          "azure_deployment_id": "gpt-4.1-mini",
          "max_tokens": 256,
          "azure_api_version": "2024-10-21"
        }
      },
      completions: {
        model: null,
        options: null,
      },
      image: {
        model: null,
        options: null
      },
      image_generation: {
        model: null,
        options: null
      },
      audio: {
        model: null,
        options: null
      },
      auth_header: 'api-key',
      auth_key: `${vars.ai_providers.AZUREAI_API_KEY}`
    },
    //aws bedrock via API does not do audio transcription or image generation or completion mode
    {
      name: 'bedrock',
      variant: 'bedrock',
      chat: {
        model: 'anthropic.claude-instant-v1',
        options: {
          "bedrock": {
            "aws_region": "ap-northeast-1"
          }
        }
      },
      completions: {
        model: null,
        options: null,
      },
      image: {
        model: null,
        options: null
      },
      image_generation: {
        model: null,
        options: null
      },
      audio: {
        model: null,
        options: null
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
  const logPath = '/tmp/ai-proxy.log'
  const logFileName = 'ai-proxy.log'
  const path = '/ai_proxy_test'
  const kongContainerName = isGwHybrid() ? 'kong-dp1' : getKongContainerName();

  let serviceId: string
  let routeId: string
  let pluginId: string
  let requestId: string

  before(async function () {
    // add header to every axios request in this suite
    axios.defaults.headers.common['Accept-Encoding'] = 'application/json,gzip,deflate'

    //create a service and route for use with plugin
    const service = await createGatewayService('ai-test-service')
    serviceId = service.id
    const route = await createRouteForService(serviceId, [path])
    routeId = route.id

    // create file log plugin
    const fileLogPlugin = {
      name: 'file-log',
      service: { id: serviceId },
      config: {
        path: logPath,
        reopen: true
      }
    }
    await createPlugin(fileLogPlugin)
    // create file for logging
    await createFileInDockerContainer(kongContainerName, logPath)
    await waitForConfigRebuild()
  })

  it('should not create AI Proxy plugin without provider', async function () {
    const pluginPayload = {
      name: 'ai-proxy',
      service: { id: serviceId },
      config: {
        model: {
          name: 'gpt-4',
        },
        auth: {
          header_name: 'Authorization',
          header_value: `Bearer ${providers[0].auth_key}`
        },
        route_type: 'llm/v1/chat'
      }
    }

    const resp = await postNegative(`${adminUrl}/services/${serviceId}/plugins`, pluginPayload)
    logResponse(resp)
    expect(resp.status, 'Status should be 400').to.equal(400)
    expect(resp.data.message, 'Should have correct error message').to.equal("schema violation (config.model: {\n  provider = \"field required for entity check\"\n})")
  })

  it('should not create AI Proxy plugin using unsupported provider', async function () {
    const pluginPayload = {
      name: 'ai-proxy',
      service: { id: serviceId },
      config: {
        model: {
          name: 'gpt-4',
          provider: 'unsupported'
        },
        auth: {
          header_name: 'Authorization',
          header_value: `Bearer ${vars.ai_providers.OPENAI_API_KEY}`
        },
        route_type: 'llm/v1/chat'
      }
    }

    const resp = await postNegative(`${adminUrl}/services/${serviceId}/plugins`, pluginPayload)
    logResponse(resp)
    expect(resp.status).to.equal(400)
    expect(resp.data.message).to.include('expected one of: openai, azure, anthropic, cohere, mistral, llama2, gemini, bedrock, huggingface')
  })

  providers.forEach((provider) => {
    if (provider.variant === 'mistral') {
      return;
    }
    // start off with chat model to test chat route type
    // not that since we are in forEach loop, the serviceId is undefined here and is not being assigned properly

    const pluginPayload = {
      name: 'ai-proxy',
      service: { id: '' },
      config: {
        model: {
          name: provider.chat.model,
          provider: provider.name,
          options: provider.chat.options || {}
        },
        genai_category: "text/generation",
        llm_format: "openai",
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
        logging: {
          log_statistics: false,
          log_payloads: false
        },
        route_type: 'llm/v1/chat',
        model_name_header: true
      }
    }

    it(`should create AI proxy plugin using ${provider.variant} provider and chat model ${provider.chat.model} model`, async function () {
      // setting service id to plugin payload as we can now access the serviceId inside it (test) scope
      pluginPayload.service.id = serviceId

      const resp = await axios({
        method: 'post',
        url: `${adminUrl}/services/${serviceId}/plugins`,
        data: pluginPayload,
        validateStatus: null
      })

      pluginId = resp.data.id
      logResponse(resp)

      expect(resp.status, 'Status should be 201').to.equal(201)
      expect(resp.headers['content-type'], 'Should have content-type header set to application/json').to.contain('application/json')
      expect(resp.data.name, 'Should have correct plugin name').to.equal('ai-proxy')

      expect(resp.data.config.model.name, 'Should have correct model name').to.equal(provider.chat.model)
      expect(resp.data.config.model.provider, 'Should have correct provider').to.equal(provider.name)
      expect(resp.data.config.auth.header_name, 'Should have correct auth header name').to.equal(provider.auth_header)
      expect(resp.data.config.auth.header_value, 'Should have correct auth header value').to.equal(provider.auth_key)
      expect(resp.data.config.route_type, 'Should have correct route type').to.equal('llm/v1/chat')

      await waitForConfigRebuild()
    })

    it(`should be able to send properly formatted chat message to ${provider.variant} provider and chat model ${provider.chat.model} via route`, async function () {
      const makeRequest = () => axios({
        method: 'post',
        url: `${proxyUrl}${path}`,
        data: {
          messages: [{
            'role': 'user',
            'content': 'What is the tallest mountain on Earth?'
          }],
        },
        validateStatus: null
      });

      await retryAIRequest(
        makeRequest,
        (resp) => evaluateAIResponseStructure(resp, provider.variant, provider.chat.model),
        provider.variant
      );
    });

    if (provider.completions.model) {
      it(`should be able to update route type from chat to completions route for ${provider.variant} AI proxy plugin`, async function () {
        const resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              route_type: 'llm/v1/completions'
            }
          }
        })
        logResponse(resp)
        expect(resp.status, 'Status should be 200').to.equal(200)
        expect(resp.data.config.route_type, 'Should have correct route type').to.equal('llm/v1/completions')

        await waitForConfigRebuild()
      })

      // since completions route type is set, attempting to use chat model should fail
      it(`should not be able to send chat formatted message to ${provider.variant} AI proxy plugin via completions route`, async function () {
        const resp = await postNegative(`${proxyUrl}${path}`, {
          messages: [{
            'role': 'user',
            'content': 'What is the capital of France?'
          }]
        })
        logResponse(resp)
        expect(resp.status, 'Should have correct status code').to.equal(400)
        expect(resp.data.error.message).to.equal('Missing required parameter: \'prompt\'.')
      })

      it(`should be able to update the model of the ${provider.variant} AI proxy plugin from chat to completions model`, async function () {
        pluginPayload.config.model.name = provider.completions.model as string
        pluginPayload.config.model.options = provider.completions.options || {}

        const resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              model: {
                name: pluginPayload.config.model.name,
                options: pluginPayload.config.model.options
              },
            }
          }
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
        expect(resp.data.config.model.name, 'Should have correct model name').to.equals(provider.completions.model)

        await waitForConfigRebuild()
      })

      // now that completions route AND completions model are set, completions message can be sent
      it(`should be able to send message to ${provider.variant} AI model ${provider.completions.model} via route with completions route type`, async function () {
        const resp = await axios({
          method: 'post',
          url: `${proxyUrl}${path}`,
          data: {
            prompt: 'What is the capital of France?',
          },
          validateStatus: null
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
        evaluateAIResponseStructure(resp, provider.variant, provider.completions.model, 'completions')
      })

      it(`should be able to enable logging statistics for ${provider.variant} AI proxy plugin`, async function () {
        const resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              logging: {
                log_statistics: true
              }
            }
          }
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
        expect(resp.data.config.logging.log_statistics, 'Should have log_statistics enabled').to.be.true

        await waitForConfigRebuild()
      })

      it(`should see statistics in logs when log_statistics is enabled for ${provider.variant} AI proxy plugin`, async function () {
        const resp = await axios({
          method: 'post',
          url: `${proxyUrl}${path}`,
          data: {
            prompt: 'It was on a dreary night of November'
          },
          validateStatus: null
        })
        logResponse(resp)
        evaluateAIResponseStructure(resp, provider.variant, provider.completions.model, 'completions')
        requestId = resp.headers['x-kong-request-id']

        await checkFileExistsInDockerContainer(kongContainerName, logPath);

        await eventually(async () => {
          copyFileFromDockerContainer(kongContainerName, logPath);
          const logContent = getTargetFileContent(logFileName);
          expect(logContent, 'should contain request id').to.contain(requestId)
          expect(logContent, 'should contain model name').to.contain(provider.completions.model)
          expect(logContent, 'should contain usage statistics').to.contain('usage')
          const regex = new RegExp(`"prompt_tokens":\\d`)
          expect(logContent, 'should include prompt token usage').to.match(regex)
        })
      })

      it(`should be able to enable logging payloads for ${provider.variant} AI proxy plugin`, async function () {
        const resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              logging: {
                log_payloads: true,
                log_statistics: false
              }
            }
          }
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
        expect(resp.data.config.logging.log_payloads, 'Should have log_payloads enabled').to.be.true

        await waitForConfigRebuild()
      })

      // Unskip when https://konghq.atlassian.net/browse/KAG-6013 is resolved
      it.skip(`should see payloads in logs when log_payload is enabled for ${provider.variant} AI proxy plugin`, async function () {
        const resp = await axios({
          method: 'post',
          url: `${proxyUrl}${path}`,
          data: {
            prompt: 'It was a dark and stormy night'
          },
          validateStatus: null
        })
        logResponse(resp)
        evaluateAIResponseStructure(resp, provider.variant, provider.completions.model, 'completions')
        requestId = resp.headers['x-kong-request-id']

        // wait for logs to appear
        await eventually(async () => {
          copyFileFromDockerContainer(kongContainerName, logPath);
          const logContent = getTargetFileContent(logFileName);
          console.log(logContent)

          expect(logContent).to.contain('\\"prompt\\":\\"It was a dark and stormy night\\"')
          expect(logContent).to.contain(`\\"model\\": \\"${provider.completions.model}\\"`)
        })

        // delete log file before next test
        await deleteFileFromDockerContainer(kongContainerName, logPath)
        // remove file from local machine
        deleteTargetFile(logFileName)
      })

      it(`should be able to disable logging for ${provider.variant} AI proxy plugin`, async function () {
        const resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              logging: {
                log_statistics: false,
                log_payloads: false
              }
            }
          }
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
        expect(resp.data.config.logging.log_statistics, 'Should have log_statistics disabled').to.be.false
        expect(resp.data.config.logging.log_payloads, 'Should have log_payloads disabled').to.be.false

        await waitForConfigRebuild()
      })

      it(`should not log payload and statistics when logging is disabled for ${provider.variant} AI proxy plugin`, async function () {
        await eventually(async () => {
          const resp = await axios({
            method: 'post',
            url: `${proxyUrl}${path}`,
            data: {
              prompt: 'It was the best of times, it was the worst of times'
            },
            validateStatus: null
          })
          logResponse(resp)
          evaluateAIResponseStructure(resp, provider.variant, provider.completions.model, 'completions')
          requestId = resp.headers['x-kong-request-id']

          // check logs for no request
          copyFileFromDockerContainer(kongContainerName, logPath);
          const logContent = getTargetFileContent(logFileName);

          deleteTargetFile(logFileName)
          await deleteFileFromDockerContainer(kongContainerName, logPath)

          expect(logContent, 'Should not contain response model').to.not.contain(`{"response_model":"${provider.completions.model}`)
          expect(logContent, 'Should not contain usage statistics').to.not.contain('{"ai-proxy":{"usage":{"prompt_tokens":')
          expect(logContent, 'Should not contain payload').to.not.contain(`{"prompt":"`)
        })
      })

    }

    it(`should be able to stream responses per request when stream is set to true for ${provider.variant} AI proxy plugin`, async function () {
      const data = {
        messages: [{
          role: 'user',
          content: 'It is a truth universally acknowledged, ...'
        }],
        stream: true
      };
      const resp = await axios({
        method: 'post',
        url: `${proxyUrl}${path}`,
        data,
        validateStatus: null
      })

      logResponse(resp)
      expect(resp.headers['content-type'], 'should have content-type header set to text/event-stream').to.contain('text/event-stream')
    })

    it(`should be able to patch the plugin to force streaming of responses for ${provider.variant} AI proxy plugin`, async function () {
      const resp = await axios({
        method: 'patch',
        url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
        data: {
          config: {
            response_streaming: 'always',
            model: {
              name: provider.chat.model, // change model to chat to test streaming
              options: provider.chat.options || {}
            },
            route_type: 'llm/v1/chat'
          }
        },
        validateStatus: null
      })
      logResponse(resp)
      expect(resp.status, 'Should have 200 status code').to.equal(200)
      expect(resp.data.config.response_streaming, 'Should have response_streaming set to always').to.equal('always')
      expect(resp.data.config.model.name, 'Should have correct model name').to.equal(provider.chat.model)
      expect(resp.data.config.route_type, 'Should have correct route type').to.equal('llm/v1/chat')

      await waitForConfigRebuild()
    })

    it(`should be able to send message to ${provider.variant} AI model ${provider.chat.model} via route with streaming enabled`, async function () {
      const makeRequest = () => axios({
        method: 'post',
        url: `${proxyUrl}${path}`,
        data: {
          messages: [{
            'role': 'user',
            'content': 'What does DNA stand for?'
          }],
          stream: true,
          model: provider.chat.model
        },
        validateStatus: null
      });

      await retryAIRequest(
        makeRequest,
        (resp) => {
          // Simple validation with just two expectations
          expect(resp.status, 'Should have 200 status code').to.equal(200);
          expect(resp.headers['content-type'], 'should have content-type header set to text/event-stream').to.contain('text/event-stream')
          return resp; // Return the response
        },
        provider.variant
      );
    })

    it(`should be able to turn off streaming of all responses for ${provider.variant} AI proxy plugin`, async function () {
      const resp = await axios({
        method: 'patch',
        url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
        data: {
          config: {
            response_streaming: 'deny'
          }
        }
      })
      logResponse(resp)
      expect(resp.status, 'Should have 200 status code').to.equal(200)
      expect(resp.data.config.response_streaming, 'Should have response_streaming set to deny').to.equal('deny')

      await waitForConfigRebuild()
    })

    it(`should not be able to request streaming of responses for ${provider.variant} AI proxy plugin`, async function () {
      const resp = await postNegative(`${proxyUrl}${path}`, {
        messages: [{
          'role': 'user',
          'content': 'Who painted the Mona Lisa?'
        }],
        stream: true
      })
      logResponse(resp)
      expect(resp.status, 'Should have 400 status code').to.equal(400)
      expect(resp.data.error.message, 'Should have correct error message').to.equal('response streaming is not enabled for this LLM')
    })

    it(`should be able to change route_type to 'preserve' for ${provider.variant} AI proxy plugin`, async function () {
      //update route to match chat completions type for 'preserve' arg
      let resp = await patchRoute(routeId, { paths: ['/v1/chat/completions'] })
      expect(resp.status, 'Should have 200 status code').to.equal(200)
      expect(resp.data.paths, 'Should have correct path').to.contain('/v1/chat/completions')

      resp = await axios({
        method: 'patch',
        url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
        data: {
          config: {
            route_type: 'preserve',
          }
        }
      })
      logResponse(resp)
      expect(resp.status, 'Should have 200 status code').to.equal(200)

      await waitForConfigRebuild()
    })

    it(`should preserve route when message is sent to ${provider.variant} AI model`, async function () {
      //skip providers do not support preserve route type yet
      if (excludedCompletionVariants.has(provider.variant)) return;

      const makeRequest = () => axios({
        method: 'post',
        url: `${proxyUrl}/v1/chat/completions`,
        data: {
          messages: [{
            'role': 'user',
            'content': 'What is the tallest mountain on Earth?'
          }],
          model: provider.chat.model
        },
        validateStatus: null
      });

      await retryAIRequest(
        makeRequest,
        (resp) => {
          // Call evaluateAIResponseStructure with all required parameters
          evaluateAIResponseStructure(resp, provider.name, provider.chat.model);
          return resp; // Return the response
        },
        provider.variant
      );
    })

    if (provider.image.model) {
      it(`should be able to update model to image model ${provider.image.model} for ${provider.variant} AI proxy plugin`, async function () {
        const resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              route_type: 'llm/v1/chat',
              model: {
                name: provider.image.model,
                options: provider.image.options || {}
              }
            }
          },
          validateStatus: null
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)

        await waitForConfigRebuild()
      })

      // skipping until https://konghq.atlassian.net/browse/KAG-6005 is resolved
      it.skip(`should be able to send image to ${provider.variant} AI model ${provider.image.model} via route`, async function () {
        // Read the image file and convert it to Base64
        const imageBase64 = fs.readFileSync('support/data/ai/image.jpg', 'base64');
        console.log(imageBase64)
        const resp = await axios({
          method: 'post',
          url: `${proxyUrl}/v1/chat/completions`,
          data: {
            messages: [{
              'role': 'user',
              'content': [{
                "type": "text",
                "text": "What's in this image?"
              },
              {
                "type": "image_url",
                "image_url": {
                  "url": `data:image/jpeg;base64,${imageBase64}`
                }
              }]
            }],
            model: provider.image.model
          },
          validateStatus: null
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
        evaluateAIResponseStructure(resp, provider.variant, provider.image.model, 'chat', false)
        // expect a reference to the moon
        expect(resp.data.choices[0].text, 'Response should have text property').to.contain('moon')
      })
    }

    if (provider.audio.model) {
      it(`should be able to update model to audio model ${provider.audio.model} for ${provider.variant} AI proxy plugin`, async function () {
        //update route to match chat completions type for 'preserve' arg
        let resp = await patchRoute(routeId, { paths: ['/v1/audio/transcriptions'] })
        expect(resp.status).to.equal(200)

        resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              route_type: 'audio/v1/audio/transcriptions',
              genai_category: "audio/transcription",
              model: {
                name: provider.audio.model,
                options: provider.audio.options || {}
              }
            }
          },
          validateStatus: null
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
        expect(resp.data.config.model.name, 'Should have correct model name').to.equal(provider.audio.model)

        await waitForConfigRebuild()
      })

      // skipping until https://konghq.atlassian.net/browse/KAG-6003 is resolved
      it.skip(`should be able to send audio to ${provider.variant} AI model ${provider.audio.model} via route`, async function () {
        const stream = fs.createReadStream('support/data/ai/audio.wav')
        const formData = new FormData();
        formData.append('model', provider.audio.model)
        formData.append('response_format', 'text')
        formData.append('file', stream)
        formData.append('prompt', 'Transcribe this audio file')

        // post formdata to route as form
        const resp = await axios({
          method: 'post',
          url: `${proxyUrl}/v1/audio/transcriptions`,
          data: formData,
          headers: formData.getHeaders(),
          validateStatus: null
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
        expect(resp.data, 'Response should have text property').to.have.property('text')
        expect(resp.data.text, 'Response should have transcribed text').to.contain('Now go away')
      })
    }

    if (provider.image_generation.model) {
      it(`should be able to update model to image generation model ${provider.image_generation.model} for ${provider.variant} AI proxy plugin`, async function () {
        //update route to match chat completions type for 'preserve' arg
        let resp = await patchRoute(routeId, { paths: ['/v1/images/generations'] })
        expect(resp.status).to.equal(200)

        resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              genai_category: "image/generation",
              route_type: 'image/v1/images/generations',
              model: {
                name: provider.image_generation.model,
                options: provider.image_generation.options || {}
              }
            }
          },
          validateStatus: null
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)

        await waitForConfigRebuild()
      })

      it(`should be able to send prompt to ${provider.variant} image generation model ${provider.image_generation.model} via route and receive image url`, async function () {
        const polly = createPolly('ai-proxy')

        const resp = await axios({
          method: 'post',
          url: `${proxyUrl}/v1/images/generations`,
          data: {
            prompt: 'A horse wearing a propeller hat',
          },
        })
        logResponse(resp)
        evaluateAIResponseStructure(resp, provider.variant, provider.image_generation.model, 'image_generation')
        await polly.stop()
      })
    }

    it(`should disable model header for ${provider.variant} AI proxy plugin`, async function () {
      // restore route to original
      let resp = await axios({
        method: 'patch',
        url: `${adminUrl}/services/${serviceId}/routes/${routeId}`,
        data: {
          paths: [path]
        }
      })
      expect(resp.status, 'Should have 200 status code').to.equal(200)
      expect(resp.data.paths, 'Should have correct path').to.contain(path)

      resp = await axios({
        method: 'patch',
        url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
        data: {
          config: {
            model_name_header: false,
            genai_category: "text/generation",
            route_type: 'llm/v1/chat',
            model: {
              name: provider.chat.model,
              options: provider.chat.options || {}
            },
          }
        }
      })
      logResponse(resp)
      expect(resp.status, 'Should have 200 status code').to.equal(200)

      await waitForConfigRebuild()
    })

    it(`should be able to send message to ${provider.variant} AI proxy plugin via route without model name header`, async function () {
      const makeRequest = () => axios({
        method: 'post',
        url: `${proxyUrl}${path}`,
        data: {
          messages: [{
            'role': 'user',
            'content': 'What is the tallest mountain on Earth?'
          }]
        },
        validateStatus: null
      })

      await retryAIRequest(
        makeRequest,
        (resp) => {
          evaluateAIResponseStructure(resp, provider.variant, provider.chat.model, 'chat', false);
          return resp; // Return the response
        },
        provider.variant
      );

    })

    //cover regression issue FTI-6603
    it(`should be able to remove model name from ${provider.variant} AI proxy plugin`, async function () {
      if (provider.variant !== 'openai') return;
      const resp = await axios({
        method: 'patch',
        url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
        data: {
          config: {
            model_name_header: true,
            route_type: 'llm/v1/chat',
            model: {
              name: null,
              options: {},
              provider: provider.name
            },
          }
        }
      })
      logResponse(resp)
      expect(resp.status, 'Should have 200 status code').to.equal(200)

      await waitForConfigRebuild()
    })

    //cover regression issue FTI-6603
    it(`should be able to send message to ${provider.variant} AI proxy plugin via route with different custmoized model name`, async function () {
      if (provider.variant !== 'openai') return;

      const models = ['gpt-4', 'gpt-4.1'];

      for (const model of models) {
        const makeRequest = () => axios({
          method: 'post',
          url: `${proxyUrl}${path}`,
          data: {
            messages: [{
              'role': 'user',
              'content': 'What is the tallest mountain on Earth?'
            }],
            model
          },
          validateStatus: null
        });

        await retryAIRequest(
          makeRequest,
          (resp) => {
            // Call evaluateAIResponseStructure with all required parameters
            evaluateAIResponseStructure(resp, provider.variant, provider.chat.model);
            // Additional assertion specific to this test
            expect(resp.headers['x-kong-llm-model'], `Response should use model "${model}" as specified in request`).to.include(model);
            return resp;
          },
          provider.variant
        );
      }

    })

    it('should delete AI proxy plugin', async function () {
      const resp = await axios({
        method: 'delete',
        url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`
      })
      logResponse(resp)
      expect(resp.status, 'Should have 204 status code').to.equal(204)
    })
  })

  after(async function () {
    delete axios.defaults.headers.common['Accept-Encoding'];
    await clearAllKongResources()
    // delete the ai-proxy.log from the container and locally
    deleteTargetFile(logFileName)
    await deleteFileFromDockerContainer(kongContainerName, logPath)
  });
});
