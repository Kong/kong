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
  copyFileFromDockerContainer,
  deleteFileFromDockerContainer,
  getTargetFileContent,
  postNegative,
  eventually,
  deleteTargetFile,
  createPolly,
} from '@support'

describe('Gateway Plugins: AI Proxy', function () {
  // add header to every axios request in this suite
  axios.defaults.headers.common['Accept-Encoding'] = 'application/json,gzip,deflate'

  const providers = [
    {
      name: 'openai',
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
      auth_key: `Bearer ${vars.ai_providers.OPENAI_API_KEY}`,
    },
    //mistral via API does not do audio transcription or image generation
    {
      name: 'mistral',
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
    }
  ]

  const adminUrl = getBasePath({
    environment: isGateway() ? Environment.gateway.admin : undefined,
  })
  const proxyUrl = getBasePath({
    environment: isGateway() ? Environment.gateway.proxy : undefined,
  })

  const path = '/ai_proxy_test'
  const kongContainerName = isGwHybrid() ? 'kong-dp1' : getKongContainerName();

  let serviceId: string
  let routeId: string
  let pluginId: string
  let requestId: string

  function evaluateResponse(resp, expectedProvider, expectedModel, type='chat') {
    expect(resp.status, 'Response should have status code 200').to.equal(200)

    switch (type) {
      case 'chat':
        expect(resp.data, 'Response should have id property').to.have.property('id')
        expect(resp.data, 'Response should have model property').to.have.property('model')
        expect(resp.data, 'Response should have choices property').to.have.property('choices')
        expect(resp.data.model, 'Response should have expected model').to.contain(expectedModel)
        expect(resp.data.choices[0], 'Response should have message property').to.have.property('message')
        expect(resp.data.choices[0].message, 'Response should have role property').to.have.property('role') 
        expect(resp.data.choices[0].message, 'Response should have content property').to.have.property('content')
        break;
      case 'completions':
        expect(resp.data, 'Response should have id property').to.have.property('id')
        expect(resp.data, 'Response should have model property').to.have.property('model')
        expect(resp.data, 'Response should have choices property').to.have.property('choices')
        expect(resp.data.model, 'Response should have expected model').to.contain(expectedModel)
        expect(Object.keys(resp.data.choices[0])).to.include.oneOf(['text', 'message']);
        break;
      case 'image_generation':
        console.log(resp.data.data)
        expect(resp.data, 'Response should have data property').to.have.property('data')
        expect(resp.data.data[0], 'Response data should have url property').to.have.property('url')
        expect(resp.data.data[0].url, 'Url should contain image link').to.contain('png')
        break;
    }
    
    //assumes that model_name_header is true
    expect(resp.headers, 'Response should have x-kong-llm-model header').to.have.property('x-kong-llm-model')
    expect(resp.headers['x-kong-llm-model'], 'Response header should have expected model and provider').to.contain(expectedModel).and.to.contain(expectedProvider)
  }

  before(async function () {
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
        path: '/tmp/ai-proxy.log',
        reopen: true
      }
    }
    await createPlugin(fileLogPlugin)
    // create file for logging
    await createFileInDockerContainer(kongContainerName, '/tmp/ai-proxy.log')
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
    providers.forEach((provider) => {
      expect(resp.data.message).to.include(provider.name)
    })
  })

  providers.forEach((provider) => {
    if (provider.name === 'mistral') {
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
        auth: {
          header_name: 'Authorization',
          header_value: provider.auth_key
        },
        logging: {
          log_statistics: false,
          log_payloads: false
        },
        route_type: 'llm/v1/chat',
        model_name_header: true
      }
    }

    it(`should create AI proxy plugin using ${provider.name} provider and chat model ${provider.chat.model} model`, async function () {
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
      expect(resp.data.config.auth.header_name, 'Should have correct auth header name').to.equal('Authorization') 
      expect(resp.data.config.auth.header_value, 'Should have correct auth header value').to.equal(provider.auth_key)
      expect(resp.data.config.route_type, 'Should have correct route type').to.equal('llm/v1/chat') 

      await waitForConfigRebuild()
    })
    
    it(`should be able to send properly formatted chat message to ${provider.name} provider and chat model ${provider.chat.model} via route`, async function () {
      const resp = await axios({
        method: 'post',
        url: `${proxyUrl}${path}`,
        data: {
          messages: [{
            'role': 'user',
            'content': 'What is the tallest mountain on Earth?'
          }],
        },
      })
     
      evaluateResponse(resp, provider.name, provider.chat.model)
    })

    it(`should be able to update route type from chat to completions route for ${provider.name} AI proxy plugin`, async function () {
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
    it(`should not be able to send chat formatted message to ${provider.name} AI proxy plugin via completions route`, async function () {
      const resp = await postNegative(`${proxyUrl}${path}`, {
        messages: [{
          'role': 'user',
          'content': 'What is the capital of France?'
        }]
      })
      logResponse(resp)
      expect(resp.status, 'Should have correct status code').to.equal(400)
      expect(resp.data.error.message).to.equal('[llm/v1/chat] message format is not compatible with [llm/v1/completions] route type')
    })

    it(`should be able to update the model of the ${provider.name} AI proxy plugin from chat to completions model`, async function () {
      pluginPayload.config.model.name = provider.completions.model
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
    it(`should be able to send message to ${provider.name} AI model ${provider.completions.model} via route with completions route type`, async function () {
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
      evaluateResponse(resp, provider.name, provider.completions.model, 'completions')
    })

    it(`should be able to enable logging statistics for ${provider.name} AI proxy plugin`, async function () {
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

    it(`should see statistics in logs when log_statistics is enabled for ${provider.name} AI proxy plugin`, async function () {
      const resp = await axios({
        method: 'post',
        url: `${proxyUrl}${path}`,
        data: {
          prompt: 'It was on a dreary night of November'
        },
        validateStatus: null
      })
      logResponse(resp) 
      evaluateResponse(resp, provider.name, provider.completions.model, 'completions')
      requestId = resp.headers['x-kong-request-id']

      await eventually(async () => {
        copyFileFromDockerContainer(kongContainerName, `/tmp/ai-proxy.log`);
        const logContent = getTargetFileContent('ai-proxy.log');
        expect(logContent, 'should contain request id').to.contain(requestId)
        expect(logContent, 'should contain model name').to.contain(provider.completions.model)
        expect(logContent, 'should contain usage statistics').to.contain('usage')
        const regex = new RegExp(`"prompt_tokens":\\d`)
        expect(logContent, 'should include prompt token usage').to.match(regex)
      }) // eslint-disable-line no-restricted-syntax
    })

    it(`should be able to enable logging payloads for ${provider.name} AI proxy plugin`, async function () {
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
    it.skip(`should see payloads in logs when log_payload is enabled for ${provider.name} AI proxy plugin`, async function () {
      const resp = await axios({
        method: 'post',
        url: `${proxyUrl}${path}`,
        data: {
          prompt: 'It was a dark and stormy night'
        },
        validateStatus: null
      })
      logResponse(resp)
      evaluateResponse(resp, provider.name, provider.completions.model, 'completions')
      requestId = resp.headers['x-kong-request-id']

      // wait for logs to appear
      await eventually(async () => {
        copyFileFromDockerContainer(kongContainerName, `/tmp/ai-proxy.log`);
        const logContent = getTargetFileContent('ai-proxy.log');
        console.log(logContent)
  
        expect(logContent).to.contain('\\"prompt\\":\\"It was a dark and stormy night\\"')
        expect(logContent).to.contain(`\\"model\\": \\"${provider.completions.model}\\"`)
      })

      // delete log file before next test
      await deleteFileFromDockerContainer(kongContainerName, '/tmp/ai-proxy.log')
      // remove file from local machine
      deleteTargetFile('ai-proxy.log')
    })
    
    it(`should be able to disable logging for ${provider.name} AI proxy plugin`, async function () {
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
 
    it(`should not log payload and statistics when logging is disabled for ${provider.name} AI proxy plugin`, async function () {
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
        evaluateResponse(resp, provider.name, provider.completions.model, 'completions')
        requestId = resp.headers['x-kong-request-id']
      
        // check logs for no request
        copyFileFromDockerContainer(kongContainerName, `/tmp/ai-proxy.log`);
        const logContent = getTargetFileContent('ai-proxy.log');

        deleteTargetFile('ai-proxy.log')
        await deleteFileFromDockerContainer(kongContainerName, '/tmp/ai-proxy.log')
    
        expect(logContent, 'Should not contain response model').to.not.contain(`{"response_model":"${provider.completions.model}`)
        expect(logContent, 'Should not contain usage statistics').to.not.contain('{"ai-proxy":{"usage":{"prompt_tokens":')
        expect(logContent, 'Should not contain payload').to.not.contain(`{"prompt":"`)
      })
    })

    it(`should be able to stream responses per request when stream is set to true for ${provider.name} AI proxy plugin`, async function () {
      const resp = await axios({
        method: 'post',
        url: `${proxyUrl}${path}`,
        data: {
          prompt: 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
          stream: true
        },
        validateStatus: null
      })
      
      logResponse(resp)
      expect(resp.headers['content-type'], 'should have content-type header set to text/event-stream').to.contain('text/event-stream')
    })

    it(`should be able to patch the plugin to force streaming of responses for ${provider.name} AI proxy plugin`, async function () {
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

    it(`should be able to send message to ${provider.name} AI model ${provider.chat.model} via route with streaming enabled`, async function () {
      const resp = await axios({
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
      })
      logResponse(resp)
      expect(resp.status, 'Should have 200 status code').to.equal(200)
      expect(resp.headers['content-type'], 'should have content-type header set to text/event-stream').to.contain('text/event-stream')
    })

    it(`should be able to turn off streaming of all responses for ${provider.name} AI proxy plugin`, async function () {
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

    it(`should not be able to request streaming of responses for ${provider.name} AI proxy plugin`, async function () {
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

    it(`should be able to change route_type to 'preserve' for ${provider.name} AI proxy plugin`, async function () {
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

    it(`should preserve route when message is sent to ${provider.name} AI model`, async function () {
      const resp = await axios({
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
      })
      logResponse(resp)
      evaluateResponse(resp, provider.name, provider.chat.model)
    })

    if (provider.image.model) {
      it(`should be able to update model to image model ${provider.image.model} for ${provider.name} AI proxy plugin`, async function () {
        const resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              model: {
                name: provider.image.model,
                options: provider.image.options || {}
              }
            }
          }
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
  
        await waitForConfigRebuild()
      })

      // skipping until https://konghq.atlassian.net/browse/KAG-6005 is resolved
      it.skip(`should be able to send image to ${provider.name} AI model ${provider.image.model} via route`, async function () {
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
        evaluateResponse(resp, provider.name, provider.image.model)
        // expect a reference to the moon
        expect(resp.data.choices[0].text, 'Response should have text property').to.contain('moon')
      })
    }
    
    if (provider.audio.model) {
      it(`should be able to update model to audio model ${provider.audio.model} for ${provider.name} AI proxy plugin`, async function () {
        //update route to match chat completions type for 'preserve' arg
        let resp = await patchRoute(routeId, { paths: ['/v1/audio/transcriptions'] })
        expect(resp.status).to.equal(200)

        resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              model: {
                name: provider.audio.model,
                options: provider.audio.options || {}
              }
            }
          }
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
        expect(resp.data.config.model.name, 'Should have correct model name').to.equal(provider.audio.model)

        await waitForConfigRebuild()
      })

      // skipping until https://konghq.atlassian.net/browse/KAG-6003 is resolved
      it.skip(`should be able to send audio to ${provider.name} AI model ${provider.audio.model} via route`, async function () {
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
      it(`should be able to update model to image generation model ${provider.image_generation.model} for ${provider.name} AI proxy plugin`, async function () {
        //update route to match chat completions type for 'preserve' arg
        let resp = await patchRoute(routeId, { paths: ['/v1/images/generations'] })
        expect(resp.status).to.equal(200)

        resp = await axios({
          method: 'patch',
          url: `${adminUrl}/services/${serviceId}/plugins/${pluginId}`,
          data: {
            config: {
              model: {
                name: provider.image_generation.model,
                options: provider.image_generation.options || {}
              }
            }
          }
        })
        logResponse(resp)
        expect(resp.status, 'Should have 200 status code').to.equal(200)
        
        await waitForConfigRebuild()
      })

      it(`should be able to send prompt to ${provider.name} image generation model ${provider.image_generation.model} via route and receive image url`, async function () {
        const polly =createPolly('ai-proxy')

        const resp = await axios({
          method: 'post',
          url: `${proxyUrl}/v1/images/generations`,
          data: {
            prompt: 'A horse wearing a propeller hat',
          },
        })
        logResponse(resp) 
        evaluateResponse(resp, provider.name, provider.image_generation.model, 'image_generation')
        await polly.stop()
      })
    } 

    it(`should disable model header for ${provider.name} AI proxy plugin`, async function () {
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

    it(`should be able to send message to ${provider.name} AI proxy plugin via route without model name header`, async function () {
      const resp = await axios({
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

      logResponse(resp)
      expect(resp.status, 'Should have 200 status code').to.equal(200)
      expect(resp.headers, 'Response should not have x-kong-llm-model header').to.not.have.property('x-kong-llm-model')
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
    await clearAllKongResources()
    // delete the ai-proxy.log from the container and locally
    deleteTargetFile('ai-proxy.log')
    await deleteFileFromDockerContainer(kongContainerName, '/tmp/ai-proxy.log')
  });
});
