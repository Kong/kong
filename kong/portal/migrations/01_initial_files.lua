return {
  {
    type = "page",
    name = "documentation/loader",
    contents = [[{{#> layout pageTitle="DevPortal - Documentation" }}

  {{#*inline "content-block"}}
    <div class="app-container">
      <div class="container">
        {{> spec/sidebar}} 
        {{> spec/renderer}}
      </div>
    </div>
  {{/inline}}

{{/layout}}
]],
    auth = true
  },
  {
    type = "page",
    name = "guides/index",
    contents = [[{{#> layout pageTitle="Dev Portal - Guides"}}

  {{#* inline "content-block"}}
    <div class="app-container">
      <div id="guides" class="container column">
        <section class="hero">
          <div class="row">
            <h1>Guides</h1>
          </div>
        </section>
        <section class="getting-started">
          <div class="row">
            <h2>Getting Started</h2>
          </div>
          <div class="row container guides">
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p><strong>Introduction</strong></p>
                <p>Get familiar with Kong EE.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/kong-ee-introduction/">Continue Reading &rsaquo;</a>
              </div>
            </div>
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p><strong>5-Minutes guide to Kong EE</strong></p>
                <p>Learn the basics of Kong, make your first API Call.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/5-minute-quickstart/" >Continue Reading &rsaquo;</a>
              </div>
            </div>
          </div>
          <div class="row">
            <h2>Customization</h2>
          </div>
          <div class="row container guides">
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p><strong>Uploading a Specification File</strong></p>
                <p>Upload your first Spec File.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/uploading-spec/" >Continue Reading &rsaquo;</a>
              </div>
            </div>
            <div class="column guide"></div>
          </div>
          <div class="row">
            <h2>Guides & References</h2>
          </div>
          <div class="row container guides">
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p><strong>Intro to Kong Vitals</strong></p>
                <p>Integrate data from Kong to your favorite monitoring tool.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/kong-vitals/" >Continue Reading &rsaquo;</a>
              </div>
            </div>
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p><strong>Kong Architecture</strong></p>
                <p>Learn the purpose and architecture of Kongs underlying components.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/kong-architecture-overview/" >Continue Reading &rsaquo;</a>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
  {{/inline}}
{{/layout}}
]],
    auth = true
  },
  {
    type = "page",
    name = "documentation/index",
    contents = [[{{#> layout pageTitle="DevPortal"}}
  {{#*inline "content-block"}}

    <div class="app-container">
      {{> spec/index-vue }}
    </div>

  {{/inline}}
{{/layout}}
]],
    auth = true
  },
  {
    type = "partial",
    name = "layout",
    contents = [[{{#if pageTitle}}
  {{> unauthenticated/title }}
{{/if}}

{{#> styles-block}}
  {{!--
    These are the default styles, but can be overridden.
  --}}
  {{> unauthenticated/assets/app-css }}
  {{> unauthenticated/custom-css}}
{{/styles-block}}

{{#> header-block}}
  {{!--
    The `header` partial is the default content, but can be overridden.
  --}}
  {{> header }}
{{/header-block}}

{{#> content-block}}
  {{!-- Default content goes here. --}}
{{/content-block}}

{{#> footer-block}}
  {{!--
    The `footer` partial is the default content, but can be overridden.
  --}}
  {{> footer }}
{{/footer-block}}

{{#> scripts-block}}
  {{> custom-js}}
  {{> unauthenticated/auth-js auth=authData.authType}}
{{/scripts-block}}
]],
    auth = true
  },
  {
    type = "page",
    name = "unauthenticated/login",
    contents = [[{{#> unauthenticated/layout pageTitle="Login" }}

{{#*inline "content-block"}}

<div class="authentication">
  {{#unless authData.authType}}
      <h1>404 - Not Found</h1>
  {{/unless}}
  {{#if authData.authType}}
    <h1>Login</h1>
    <form id="login">
      {{#if (eq authData.authType 'basic-auth')}}
        <label for="username">Email</label>
        <input id="username" type="text" name="username" required />
        <label for="password">Password</label>
        <input id="password" type="password" name="password" required />
        <button id="login-button" class="button button-primary" type="submit">Login</button>
        <a class="forgot-password" href="{{config.PORTAL_GUI_URL}}/reset-password">Forgot Password?</a>
      {{/if}}
      {{#if (eq authData.authType 'key-auth')}}
        <label for="key">Api Key</label>
        <input id="key" type="text" name="key" required />
        <button id="login-button" class="button button-primary" type="submit">Login</button>
        <a class="forgot-password" href="{{config.PORTAL_GUI_URL}}/reset-password">Forgot Key?</a>
      {{/if}}

      {{#if (eq authData.authType 'openid-connect')}}
      <a href="{{config.PORTAL_API_URL}}{{config.WORKSPACE_PATH}}/auth" class="button button-outline">
        <svg class="google-button-icon" viewBox="0 0 366 372" xmlns="http://www.w3.org/2000/svg"><path d="M125.9 10.2c40.2-13.9 85.3-13.6 125.3 1.1 22.2 8.2 42.5 21 59.9 37.1-5.8 6.3-12.1 12.2-18.1 18.3l-34.2 34.2c-11.3-10.8-25.1-19-40.1-23.6-17.6-5.3-36.6-6.1-54.6-2.2-21 4.5-40.5 15.5-55.6 30.9-12.2 12.3-21.4 27.5-27 43.9-20.3-15.8-40.6-31.5-61-47.3 21.5-43 60.1-76.9 105.4-92.4z" id="Shape" fill="#EA4335"/><path d="M20.6 102.4c20.3 15.8 40.6 31.5 61 47.3-8 23.3-8 49.2 0 72.4-20.3 15.8-40.6 31.6-60.9 47.3C1.9 232.7-3.8 189.6 4.4 149.2c3.3-16.2 8.7-32 16.2-46.8z" id="Shape" fill="#FBBC05"/><path d="M361.7 151.1c5.8 32.7 4.5 66.8-4.7 98.8-8.5 29.3-24.6 56.5-47.1 77.2l-59.1-45.9c19.5-13.1 33.3-34.3 37.2-57.5H186.6c.1-24.2.1-48.4.1-72.6h175z" id="Shape" fill="#4285F4"/><path d="M81.4 222.2c7.8 22.9 22.8 43.2 42.6 57.1 12.4 8.7 26.6 14.9 41.4 17.9 14.6 3 29.7 2.6 44.4.1 14.6-2.6 28.7-7.9 41-16.2l59.1 45.9c-21.3 19.7-48 33.1-76.2 39.6-31.2 7.1-64.2 7.3-95.2-1-24.6-6.5-47.7-18.2-67.6-34.1-20.9-16.6-38.3-38-50.4-62 20.3-15.7 40.6-31.5 60.9-47.3z" fill="#34A853"/></svg>
        <span class="google-button-text">Sign in with Google</span>
      </a>
      {{/if}}
    </form>
  {{/if}}
</div>

{{/inline}}

{{/unauthenticated/layout}}

<!-- Autofill email field from UTM parameter -->
<script>
  function getUrlVars() {
    var vars = {}
    var parts = window.location.href.replace(/[?&]+([^=&]+)=([^&]*)/gi, function(m,key,value) {
      vars[key] = value
    })
    return vars
  }

  function getUrlParam(parameter, defaultvalue){
    var urlparameter = defaultvalue;
    if(window.location.href.indexOf(parameter) > -1){
      urlparameter = getUrlVars()[parameter];
    }
    return urlparameter;
  }

  var usernameEl = document.getElementById('username')
  if (usernameEl) {
    usernameEl.value = getUrlParam('email', '')
  }
</script>

<script>
  document.getElementById('login').addEventListener('submit', e => { e.preventDefault() })
</script>

<style lang="scss">
.forgot-password {
  margin: 32px auto;
  text-align: center;
}
</style>
]],
    auth = false
  },
  {
    type = "page",
    name = "unauthenticated/404",
    contents = [[{{#> unauthenticated/layout pageTitle="404 - Page Not Found" }}

  {{#*inline "content-block"}}
    <div class="app-container error-page column">
      <h1>404</h1>
      <h2>Page not found</h2>
      <p>Sorry. We cannot find the page you were looking for.</p>
      <p>You could reload the page or go to the Homepage.</p>
      <a class="button button-primary" href="{{config.PORTAL_GUI_URL}}/">Go to Homepage</a>
    </div>
  {{/inline}}

{{/unauthenticated/layout}}
]],
    auth = false
  },
  {
    type = "page",
    name = "unauthenticated/register",
    contents = [[{{#> unauthenticated/layout pageTitle="Register" }}

{{#*inline "content-block"}}
<div class="authentication">
  {{#unless authData.authType}}
      <h1>404 - Not Found</h1>
  {{/unless}}
  {{#if authData.authType}}
    {{> unauthenticated/registration-form-vue }}
  {{/if}}
</div>
{{/inline}}

{{/unauthenticated/layout}}
]],
    auth = false
  },
  {
    type = "page",
    name = "unauthenticated/reset-password",
    contents = [[{{#> unauthenticated/layout pageTitle="Reset Password" }}

  {{#*inline "content-block"}}
    <div class="app-container">
      <div id="portal-dashboard" class="page-wrapper indent" page="reset-password"></div>
    </div>
  {{/inline}}

{{/unauthenticated/layout}}
]],
    auth = false
  },
  {
    type = "page",
    name = "search",
    contents = [[{{#> layout pageTitle="Search Results" }}

  {{#*inline "content-block"}}
    <div class="app-container">
      {{> search/results-vue }}
    </div>
  {{/inline}}

{{/layout}}
]],
    auth = true
  },
  {
    type = "partial",
    name = "common-helpers-js",
    contents = [=[<script type="text/javascript">

if (!window.helpers) {
  window.helpers = {}
}

window.helpers.goToPage = (url) => {
  window.location.href = url
}

window.helpers.getWorkspace = () => {
  return window.K_CONFIG && window.K_CONFIG.WORKSPACE
}

window.helpers.buildUrl = (path) => {
  let portalURL = window.K_CONFIG && window.K_CONFIG.PORTAL_GUI_URL
  return `${portalURL}/${path}`
}

window.helpers.getUrlParameter = (name) => {
  name = name.replace(/[[]/, '\\[').replace(/[\]]/, '\\]')
  var regex = new RegExp('[\\?&]' + name + '=([^&#]*)')
  var results = regex.exec(window.location.search)
  return results === null ? '' : decodeURIComponent(results[1].replace(/\+/g, ' '))
}

window.helpers.isValidKey = (keyCode) => {
  return (keyCode >= 48 && keyCode <= 90) || keyCode >= 186
}

window.helpers.sortAlphabetical = (a, b) => {
  if (a < b) {
    return -1
  } else if (a > b) {
    return 1
  }
  return 0
}

window.helpers.isObject = (item) => {
  return (typeof item === 'object' && !Array.isArray(item) && item !== null)
}

</script>
]=],
    auth = true
  },
  {
    type = "page",
    name = "user",
    contents = [[{{#> layout pageTitle="User Details" }}

{{#*inline "content-block"}}
<div class="app-container">
  <div class="page-wrapper indent">
    <img style="height: 75px; width: 75px; border-radius: 37px;" src="{{authData.idToken.1.picture}}"/>
    <h1>{{authData.idToken.1.name}}</h1>
    <div for="email"><b>email</b></div>
    <div id="email">{{authData.idToken.1.email}}</div>
  </div>
</div>
{{/inline}}

{{/layout}}
]],
    auth = true
  },
  {
    type = "spec",
    name = "admin",
    contents = [[{
  "swagger": "2.0",
  "info": {
    "version": "13.1.0",
    "description": "A Swagger definition for the Kong Admin API",
    "title": "Kong-Admin"
  },
  "host": "127.0.0.1:8001",
  "basePath": "/",
  "tags": [
    {
      "name": "Status",
      "description": "Kong node status"
    },
    {
      "name": "Services",
      "description": "Group Routes and apply Plugins"
    },
    {
      "name": "Routes",
      "description": "Route to upstream service endpoints"
    },
    {
      "name": "Consumers",
      "description": "Entities which can consume APIs from Kong"
    },
    {
      "name": "Plugins",
      "description": "Code which adds functionality to Kong"
    },
    {
      "name": "Certificates",
      "description": "Certificates for use in Kong"
    }
  ],
  "consumes": [
    "application/json"
  ],
  "produces": [
    "application/json"
  ],
  "paths": {
    "/": {
      "get": {
        "tags": [
          "Status"
        ],
        "description": "Get details about a node",
        "responses": {
          "200": {
            "description": "Node information returned",
            "schema": {
              "type": "object",
              "properties": {
                "hostname": {
                  "type": "string"
                },
                "node_id": {
                  "type": "string"
                },
                "lua_version": {
                  "type": "string"
                },
                "plugins": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "available_on_server": {
                        "type": "array",
                        "items": {
                          "type": "string"
                        }
                      },
                      "installed_on_server": {
                        "type": "array",
                        "items": {
                          "type": "string"
                        }
                      }
                    }
                  }
                },
                "configuration": {
                  "type": "object"
                },
                "tagline": {
                  "type": "string"
                },
                "version": {
                  "type": "number"
                }
              }
            }
          }
        }
      }
    },
    "/status": {
      "get": {
        "tags": [
          "Status"
        ],
        "description": "Get status of a node",
        "responses": {
          "200": {
            "description": "Node status information returned",
            "schema": {
              "type": "object",
              "properties": {
                "service": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "total_requests": {
                        "type": "integer"
                      },
                      "connections_active": {
                        "type": "integer"
                      },
                      "connections_accepted": {
                        "type": "integer"
                      },
                      "connections_handled": {
                        "type": "integer"
                      },
                      "connections_reading": {
                        "type": "integer"
                      },
                      "connections_writing": {
                        "type": "integer"
                      },
                      "connections_waiting": {
                        "type": "integer"
                      }
                    }
                  }
                },
                "database": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "reachable": {
                        "type": "boolean"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    "/services/": {
      "get": {
        "tags": [
          "Services"
        ],
        "description": "Get details about a service",
        "operationId": "getServices",
        "parameters": [
          {
            "name": "service_id",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "200": {
            "description": "Service was found",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "created_at": {
                  "type": "number"
                },
                "updated_at": {
                  "type": "number"
                },
                "connect_timeout": {
                  "type": "integer"
                },
                "protocol": {
                  "type": "string"
                },
                "host": {
                  "type": "string"
                },
                "port": {
                  "type": "number"
                },
                "path": {
                  "type": "string"
                },
                "name": {
                  "type": "string"
                },
                "retries": {
                  "type": "number"
                },
                "read_timeout": {
                  "type": "number"
                },
                "write_timeout": {
                  "type": "number"
                }
              }
            }
          },
          "404": {
            "description": "No such service found"
          }
        }
      },
      "post": {
        "tags": [
          "Services"
        ],
        "description": "Create a service",
        "operationId": "postServices",
        "responses": {
          "201": {
            "description": "Service was created",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "created_at": {
                  "type": "number"
                },
                "updated_at": {
                  "type": "number"
                },
                "connect_timeout": {
                  "type": "integer"
                },
                "protocol": {
                  "type": "string"
                },
                "host": {
                  "type": "string"
                },
                "port": {
                  "type": "number"
                },
                "path": {
                  "type": "string"
                },
                "name": {
                  "type": "string"
                },
                "retries": {
                  "type": "number"
                },
                "read_timeout": {
                  "type": "number"
                },
                "write_timeout": {
                  "type": "number"
                }
              }
            }
          }
        }
      },
      "patch": {
        "tags": [
          "Services"
        ],
        "description": "Update a service",
        "operationId": "pathServices",
        "parameters": [
          {
            "name": "service_id",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "200": {
            "description": "Service was updated",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "created_at": {
                  "type": "number"
                },
                "updated_at": {
                  "type": "number"
                },
                "connect_timeout": {
                  "type": "integer"
                },
                "protocol": {
                  "type": "string"
                },
                "host": {
                  "type": "string"
                },
                "port": {
                  "type": "number"
                },
                "path": {
                  "type": "string"
                },
                "name": {
                  "type": "string"
                },
                "retries": {
                  "type": "number"
                },
                "read_timeout": {
                  "type": "number"
                },
                "write_timeout": {
                  "type": "number"
                }
              }
            }
          }
        }
      },
      "delete": {
        "tags": [
          "Services"
        ],
        "description": "delete a service",
        "operationId": "deleteServices",
        "parameters": [
          {
            "name": "service_id",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "204": {
            "description": "No Content"
          }
        }
      }
    },
    "/routes/": {
      "get": {
        "tags": [
          "Routes"
        ],
        "description": "Get details about a route",
        "operationId": "getRoute",
        "parameters": [
          {
            "name": "route_id",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "200": {
            "description": "Route was found",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "created_at": {
                  "type": "number"
                },
                "updated_at": {
                  "type": "number"
                },
                "connect_timeout": {
                  "type": "integer"
                },
                "protocol": {
                  "type": "string"
                },
                "host": {
                  "type": "string"
                },
                "port": {
                  "type": "number"
                },
                "path": {
                  "type": "string"
                },
                "name": {
                  "type": "string"
                },
                "retries": {
                  "type": "number"
                },
                "read_timeout": {
                  "type": "number"
                },
                "write_timeout": {
                  "type": "number"
                }
              }
            }
          },
          "404": {
            "description": "No such service found"
          }
        }
      },
      "post": {
        "tags": [
          "Routes"
        ],
        "description": "Create a Route",
        "operationId": "portRoute",
        "responses": {
          "201": {
            "description": "Route was created",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "created_at": {
                  "type": "number"
                },
                "updated_at": {
                  "type": "number"
                },
                "connect_timeout": {
                  "type": "integer"
                },
                "protocol": {
                  "type": "string"
                },
                "host": {
                  "type": "string"
                },
                "port": {
                  "type": "number"
                },
                "path": {
                  "type": "string"
                },
                "name": {
                  "type": "string"
                },
                "retries": {
                  "type": "number"
                },
                "read_timeout": {
                  "type": "number"
                },
                "write_timeout": {
                  "type": "number"
                }
              }
            }
          }
        }
      },
      "patch": {
        "tags": [
          "Routes"
        ],
        "description": "Update a route",
        "operationId": "patchRoute",
        "parameters": [
          {
            "name": "route_id",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "200": {
            "description": "Route was updated",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "created_at": {
                  "type": "number"
                },
                "updated_at": {
                  "type": "number"
                },
                "connect_timeout": {
                  "type": "integer"
                },
                "protocol": {
                  "type": "string"
                },
                "host": {
                  "type": "string"
                },
                "port": {
                  "type": "number"
                },
                "path": {
                  "type": "string"
                },
                "name": {
                  "type": "string"
                },
                "retries": {
                  "type": "number"
                },
                "read_timeout": {
                  "type": "number"
                },
                "write_timeout": {
                  "type": "number"
                }
              }
            }
          }
        }
      },
      "delete": {
        "tags": [
          "Routes"
        ],
        "description": "Delete a Route",
        "operationId": "deleteRoute",
        "parameters": [
          {
            "name": "route_id",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "204": {
            "description": "No Content"
          }
        }
      }
    },
    "/consumers/{id_or_name}": {
      "get": {
        "description": "Get details about a consumer",
        "tags": [
          "Consumers"
        ],
        "operationId": "getConsumersByIdName",
        "parameters": [
          {
            "name": "id_or_name",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "200": {
            "description": "Consumer was found",
            "schema": {
              "type": "object",
              "properties": {
                "custom_id": {
                  "type": "string"
                },
                "username": {
                  "type": "string"
                },
                "created_at": {
                  "type": "integer"
                }
              }
            }
          },
          "404": {
            "description": "No such consumer found"
          }
        }
      }
    },
    "/consumers/": {
      "post": {
        "description": "Create a consumer",
        "operationId": "postConsumers",
        "tags": [
          "Consumers"
        ],
        "consumes": [
          "application/x-www-form-urlencoded"
        ],
        "parameters": [
          {
            "name": "username",
            "in": "formData",
            "type": "string",
            "required": true
          },
          {
            "name": "custom_id",
            "in": "formData",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "201": {
            "description": "Consumer created",
            "schema": {
              "type": "object",
              "properties": {
                "custom_id": {
                  "type": "string"
                },
                "username": {
                  "type": "string"
                },
                "created_at": {
                  "type": "integer"
                }
              }
            }
          }
        }
      },
      "patch": {
        "description": "Update a consumer",
        "operationId": "patchConsumers",
        "consumes": [
          "application/x-www-form-urlencoded"
        ],
        "tags": [
          "Consumers"
        ],
        "parameters": [
          {
            "name": "username",
            "in": "formData",
            "type": "string",
            "required": true
          },
          {
            "name": "custom_id",
            "in": "formData",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "200": {
            "description": "Consumer was updated",
            "schema": {
              "type": "object",
              "properties": {
                "custom_id": {
                  "type": "string"
                },
                "username": {
                  "type": "string"
                },
                "created_at": {
                  "type": "integer"
                }
              }
            }
          }
        }
      },
      "delete": {
        "description": "Delete a consumer",
        "operationId": "deleteConsumers",
        "tags": [
          "Consumers"
        ],
        "parameters": [
          {
            "name": "id_or_name",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "204": {
            "description": "No content"
          },
          "404": {
            "description": "No such consumer found"
          }
        }
      }
    },
    "/plugins/{id_or_name}": {
      "get": {
        "tags": [
          "Plugins"
        ],
        "operationId": "getPluginsByIdName",
        "parameters": [
          {
            "name": "id_or_name",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "description": "Get details about a plugin",
        "responses": {
          "200": {
            "description": "Plugin information returned",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "service_id": {
                  "type": "string"
                },
                "consumer_id": {
                  "type": "string"
                },
                "name": {
                  "type": "string"
                },
                "config": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "minute": {
                        "type": "number"
                      },
                      "hour": {
                        "type": "number"
                      }
                    }
                  }
                },
                "enabled": {
                  "type": "boolean"
                },
                "created_at": {
                  "type": "number"
                }
              }
            }
          }
        }
      },
      "patch": {
        "tags": [
          "Plugins"
        ],
        "description": "Update details about a plugin",
        "operationId": "patchPluginsByIdName",
        "consumes": [
          "application/x-www-form-urlencoded"
        ],
        "parameters": [
          {
            "name": "name",
            "in": "formData",
            "type": "string",
            "required": true
          },
          {
            "name": "consumer_id",
            "in": "formData",
            "type": "string",
            "required": false
          },
          {
            "name": "config.{property}",
            "description": "The configuration properties for the Plugin which can be found on the plugins documentation page in the Plugin Gallery",
            "in": "formData",
            "type": "string",
            "required": false
          }
        ],
        "responses": {
          "200": {
            "description": "Plugin information updated",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "service_id": {
                  "type": "string"
                },
                "consumer_id": {
                  "type": "string"
                },
                "name": {
                  "type": "string"
                },
                "config": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "minute": {
                        "type": "number"
                      },
                      "hour": {
                        "type": "number"
                      }
                    }
                  }
                },
                "enabled": {
                  "type": "boolean"
                },
                "created_at": {
                  "type": "number"
                }
              }
            }
          }
        }
      },
      "delete": {
        "tags": [
          "Plugins"
        ],
        "parameters": [
          {
            "name": "id_or_name",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "description": "Delete a plugin",
        "operationId": "deletePluginByIdName",
        "responses": {
          "204": {
            "description": "No content"
          }
        }
      }
    },
    "/plugins/": {
      "get": {
        "tags": [
          "Plugins"
        ],
        "description": "Get details about a plugin",
        "operationId": "getPlugin",
        "parameters": [
          {
            "name": "id",
            "in": "query",
            "type": "string",
            "required": false
          },
          {
            "name": "name",
            "in": "query",
            "type": "string",
            "required": false
          },
          {
            "name": "service_id",
            "in": "query",
            "type": "string",
            "required": false
          },
          {
            "name": "route_id",
            "in": "query",
            "type": "string",
            "required": false
          },
          {
            "name": "consumer_id",
            "in": "query",
            "type": "string",
            "required": false
          },
          {
            "name": "size",
            "in": "query",
            "type": "integer",
            "required": false
          },
          {
            "name": "offset",
            "description": "",
            "in": "query",
            "type": "string",
            "required": false
          }
        ],
        "responses": {
          "200": {
            "description": "Plugin information returned",
            "schema": {
              "type": "object",
              "properties": {
                "total": {
                  "type": "integer"
                },
                "data": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "id": {
                        "type": "string"
                      },
                      "service_id": {
                        "type": "string"
                      },
                      "config": {
                        "type": "object",
                        "properties": {
                          "minute": {
                            "type": "integer"
                          },
                          "hour": {
                            "type": "integer"
                          }
                        }
                      }
                    }
                  }
                },
                "enabled": {
                  "type": "boolean"
                },
                "created_at": {
                  "type": "number"
                }
              }
            }
          }
        }
      },
      "post": {
        "description": "Add a plugin to a route or service or consumer",
        "operationId": "postPlugin",
        "tags": [
          "Plugins"
        ],
        "consumes": [
          "application/x-www-form-urlencoded"
        ],
        "parameters": [
          {
            "name": "name",
            "in": "formData",
            "type": "string",
            "required": true
          },
          {
            "name": "consumer_id",
            "in": "formData",
            "type": "string",
            "required": false
          },
          {
            "name": "config.{property}",
            "description": "The configuration properties for the Plugin which can be found on the plugins documentation page in the Plugin Gallery",
            "in": "formData",
            "type": "string",
            "required": false
          }
        ],
        "responses": {
          "201": {
            "description": "Plugin created",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "service_id": {
                  "type": "string"
                },
                "consumer_id": {
                  "type": "string"
                },
                "name": {
                  "type": "string"
                },
                "config": {
                  "type": "object",
                  "properties": {
                    "minute": {
                      "type": "number"
                    },
                    "hour": {
                      "type": "number"
                    }
                  }
                },
                "enabled": {
                  "type": "boolean"
                },
                "created_at": {
                  "type": "number"
                }
              }
            }
          }
        }
      },
      "put": {
        "tags": [
          "Plugins"
        ],
        "description": "Update or create a plugin",
        "operationId": "putPlugin",
        "consumes": [
          "application/x-www-form-urlencoded"
        ],
        "parameters": [
          {
            "name": "name",
            "in": "formData",
            "type": "string",
            "required": true
          },
          {
            "name": "consumer_id",
            "in": "formData",
            "type": "string",
            "required": false
          },
          {
            "name": "config.{property}",
            "description": "The configuration properties for the Plugin which can be found on the plugins documentation page in the Plugin Gallery",
            "in": "formData",
            "type": "string",
            "required": false
          }
        ],
        "responses": {
          "200": {
            "description": "Plugin information updated"
          },
          "201": {
            "description": "Plugin created"
          }
        }
      }
    },
    "/plugins/enabled": {
      "get": {
        "description": "List enabled Plugins",
        "operationId": "getPluginsEnabled",
        "tags": [
          "Plugins"
        ],
        "responses": {
          "200": {
            "description": "Plugin list returned",
            "schema": {
              "type": "object",
              "properties": {
                "config": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "enabled_plugins": {
                        "type": "array",
                        "items": {
                          "type": "string"
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    "/plugins/schema/{plugin_name}": {
      "get": {
        "description": "Get the schema for a plugin",
        "operationId": "getPluginSchemaByName",
        "tags": [
          "Plugins"
        ],
        "parameters": [
          {
            "name": "plugin_name",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "200": {
            "description": "Plugin schema returned",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "service_id": {
                  "type": "string"
                },
                "consumer_id": {
                  "type": "string"
                },
                "name": {
                  "type": "string"
                },
                "config": {
                  "type": "object",
                  "properties": {
                    "minute": {
                      "type": "number"
                    },
                    "hour": {
                      "type": "number"
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
    "/certificates/{sni_or_id}": {
      "get": {
        "tags": [
          "Certificates"
        ],
        "description": "Get details about a certificate by SNI or ID",
        "operationId": "getCertBySNIorID",
        "parameters": [
          {
            "name": "sni_or_id",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "200": {
            "description": "Certificate information returned",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "cert": {
                  "type": "string"
                },
                "key": {
                  "type": "string"
                },
                "snis": {
                  "type": "array",
                  "items": {
                    "type": "string"
                  }
                },
                "created_at": {
                  "type": "number"
                }
              }
            }
          }
        }
      }
    },
    "/certificates/": {
      "get": {
        "tags": [
          "Certificates"
        ],
        "operationId": "getCertificates",
        "description": "Get details about a certificate",
        "parameters": [
          {
            "name": "sni_or_id",
            "in": "path",
            "type": "string",
            "required": true
          }
        ],
        "responses": {
          "200": {
            "description": "Certificate information returned",
            "schema": {
              "type": "object",
              "properties": {
                "total": {
                  "type": "integer"
                },
                "data": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "id": {
                        "type": "string"
                      },
                      "cert": {
                        "type": "string"
                      },
                      "key": {
                        "type": "string"
                      },
                      "snis": {
                        "type": "array",
                        "items": {
                          "type": "string"
                        }
                      },
                      "created_at": {
                        "type": "number"
                      }
                    }
                  }
                }
              }
            }
          }
        }
      },
      "post": {
        "tags": [
          "Certificates"
        ],
        "operationId": "postCertificates",
        "description": "Create a certificate",
        "consumes": [
          "application/x-www-form-urlencoded"
        ],
        "parameters": [
          {
            "name": "cert",
            "in": "formData",
            "type": "string",
            "required": true
          },
          {
            "name": "key",
            "in": "formData",
            "type": "string",
            "required": true
          },
          {
            "name": "sni",
            "in": "formData",
            "type": "string",
            "required": false
          }
        ],
        "responses": {
          "201": {
            "description": "Certificate created",
            "schema": {
              "type": "object",
              "properties": {
                "id": {
                  "type": "string"
                },
                "cert": {
                  "type": "string"
                },
                "key": {
                  "type": "string"
                },
                "snis": {
                  "type": "array",
                  "items": {
                    "type": "string"
                  }
                },
                "created_at": {
                  "type": "number"
                }
              }
            }
          }
        }
      }
    }
  }
}
]],
    auth = true
  },
  {
    type = "partial",
    name = "footer",
    contents = [[<footer id="footer" class="container column shrink">
  <div class="container">
    <p>&copy; {{ currentYear }} Company, Inc.</p>
    <ul class="footer-links">
      <li>
        <a href="{{config.PORTAL_GUI_URL}}/about">About</a>
      </li>
      <li>
        <a href="{{config.PORTAL_GUI_URL}}/guides">Guides</a>
      </li>
    </ul>
  </div>
</footer>
]],
    auth = true
  },
  {
    type = "page",
    name = "unauthenticated/unauthorized",
    contents = [[{{#> unauthenticated/layout pageTitle="Unauthorized" }} 

{{#*inline "content-block"}}
  <div class="app-container authentication">
      <h2>Unauthorized</h2>
      <p style="max-width: 400px; text-align: left;">You are unauthorized to view this page because you are not an approved or registered developer. Please try <a href="{{config.PORTAL_GUI_URL}}/login">logging in</a>, or <a href="{{config.PORTAL_GUI_URL}}/register">signing up</a> for access.</p>
  </div>
{{/inline}} 

{{/unauthenticated/layout}}
]],
    auth = false
  },
  {
    type = "page",
    name = "settings",
    contents = [[{{#> layout pageTitle="Dev Portal - Settings" }}

  {{#*inline "content-block"}}
    <div class="app-container">
      <div id="portal-dashboard" class="page-wrapper indent" page="settings"></div>
    </div>
  {{/inline}}

{{/layout}}
]],
    auth = true
  },
  {
    type = "page",
    name = "guides/uploading-spec",
    contents = [[{{#> layout pageTitle="Dev Portal - Uploading Spec File" }}

{{#* inline "content-block"}}
<div class="app-container">
  <div class="container">
     {{> guides/sidebar}}
        <section class="page-wrapper kong-doc">
{{#markdown}}

# Uploading a Specification file

## Option 1 - The Terminal

- Upload a Specification file with the following call in the terminal
	- In this example we are using the 
	[Swagger Petstore](http://petstore.swagger.io/v2/swagger.json)

```bash
	curl -X POST http://127.0.0.1:8001/WORKSPACE_NAME/files \
	curl -X POST http://127.0.0.1:8001/WORKSPACE_NAME/files \
	-F "type=spec" \
	-F "name=swagger" \
	-F "contents=@swagger.json" \
	-F "auth=true"
```

- Navigate to the Dev Portal [API Catalog](/documentation), the new Swagger Spec
should now be listed.

## Option 2 - The Kong Manager

- In the Kong Manager, navigate to the Dev Portal 'Specs' page in your Workspace.
- Click the button **_+ Add Spec_**
- Enter `swagger` as the file name
- Check the **_Requires Authentication_** Box
- Click the **_Create File_** button
- Copy and paste your spec file into the code editor.
- Once finished, click the **_Update File_** button.
- Back in the Dev Portal, navigate to the Dev Portal 
[API Catalog](/documentation), the new Swagger Spec should now be listed.


{{/markdown}}
</section>
</div>
</div>
{{/inline}}
{{/layout}}
]],
    auth = true
  },
  {
    type = "page",
    name = "about",
    contents = [[{{#> layout pageTitle="Dev Portal - About" }}
{{#*inline "content-block"}}
<div class="app-container">
<div class="page-wrapper indent">
{{#markdown}}
# About
This is a sample page created with markdown and handlebars. You can delete it or modify it to suit your needs.
{{/markdown}}
</div>
</div>
{{/inline}}
{{/layout}}
]],
    auth = true
  },
  {
    type = "spec",
    name = "files",
    contents = [[swagger: '2.0'
info:
  description: Developer Portal API
  title: Developer Portal Files API
  version: "1.0"
host: 127.0.0.1:8001
basePath: /
tags:
  - name: files
    description: List, edit, and delete Developer Portal Files.
schemes:
  - http
paths:
  /files:
    get:
      tags:
        - files
      summary: Get list of files
      description: ''
      operationId: getFiles
      parameters:
        - name: name
          type: string
          in: query
          description: File name
          required: false
        - name: content
          type: string
          in: query
          description: File contents
          required: false
        - name: type
          type: string
          in: query
          description: File type
          required: false
        - name: auth
          type: boolean
          in: query
          description: File is or is not authenticated
          required: false
      produces:
        - application/json
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/File'
  '/files/{name}':
    get:
      tags:
        - files
      summary: Get indiviual files
      description: ''
      operationId: getFile
      produces:
        - application/json
      parameters:
        - name: name
          type: string
          in: path
          description: File name.
          required: true
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/File'
        '404':
          description: No file found by name or id
    patch:
      tags:
        - files
      summary: Edit files
      operationId: EditFile
      parameters:
        - name: name
          type: string
          in: path
          description: File name.
          required: true
        - name: name
          type: string
          in: query
          description: File name
          required: false
        - name: content
          type: string
          in: query
          description: File contents
          required: false
        - name: type
          type: string
          in: query
          description: File type
          required: false
        - name: auth
          type: boolean
          in: query
          description: File is or is not authenticated
          required: false
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/File'
        '404':
          description: No file found by name or id
    delete:
      tags:
        - files
      summary: Delete files
      operationId: DeleteFile
      description: ''
      parameters:
        - name: name
          type: string
          in: path
          description: File name.
          required: true
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/File'
        '404':
          description: No file found by name or id
  '/files/unauthenticated':
    get:
      tags:
        - files
      summary: Unauthenticated files
      description: ''
      operationId: GetUnauthenticatedFiles
      produces:
        - application/json
      parameters:
        - name: name
          type: string
          in: path
          description: File name.
          required: true
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/File'
        '404':
          description: No file found by name or id

definitions:
  File:
    type: object
    example:
      name: 'petstore'
      type: 'spec'
      auth: true
      contents: "<h1>Hello {{name}}<h1>"
    properties:
      name:
        type: string
      type:
        type: string
      auth:
        type: boolean
      contents:
        type: string
]],
    auth = true
  },
  {
    type = "partial",
    name = "custom-js",
    contents = [[{{> unauthenticated/code-snippet-languages}}

<script type="text/javascript">
/*
|--------------------------------------------------------------------------
| Swagger UI Options
| e.g. https://github.com/swagger-api/swagger-ui/blob/master/docs/usage/configuration.md
|--------------------------------------------------------------------------

window.swaggerUIAdditionalOptions = {
  oauth2RedirectUrl: '127.0.0.1:8003'
}
*/

</script>
]],
    auth = true
  },
  {
    type = "page",
    name = "guides/kong-vitals",
    contents = [[{{#> layout pageTitle="Kong Vitals"}}

  {{#* inline "content-block"}}
    <div class="app-container">
      <div class="container">
        {{> guides/sidebar}}
        <section class="page-wrapper kong-doc">
          <h1>Kong Vitals</h1>
          <h2>What is Vitals?</h2>
          <p>The Vitals feature in Kong’s Admin API and GUI provides useful metrics about the health and performance of your Kong nodes, as well as metrics about the usage of your Kong-proxied APIs.</p>
          
          <h2>Requirements</h2>
          <p>Vitals requires PostgreSQL 9.5+ or Cassandra 2.1+.</p>
          <p>Vitals must also be enabled in Kong configuration. See below for details.</p>
          
          <h2>Enabling and Disabling Vitals</h2>
          <p>Kong Enterprise Edition ships with Vitals turned off. You can change this in your configuration:</p>

          <pre><code class="language-bash"><span class="hljs-comment"># via your Kong configuration file; e.g., kong.conf</span>
          vitals = on  <span class="hljs-comment"># vitals is enabled</span>
          vitals = off <span class="hljs-comment"># vitals is disabled</span>
          </code></pre>

          <pre><code class="language-bash"><span class="hljs-comment"># or via environment variables</span>
          $ <span class="hljs-built_in">export</span> KONG_VITALS=on
          $ <span class="hljs-built_in">export</span> KONG_VITALS=off
          </code></pre>

          <p>As with other Kong configurations, your changes take effect on kong reload or kong restart.</p>
          
          <h2>Vitals Metrics</h2>
          <p>Below is a list of metrics that Vitals currently collects. More metrics and dimensions will be added over time. To request additional metrics and dimensions, please contact Kong Support.</p>
          <p>All metrics are collected at 1-second intervals and aggregated into 1-minute intervals. The 1-second intervals are retained for one hour. The 1-minute intervals are retained for 25 hours. If you require access to this data for long periods of time, you can use the Vitals API to pull it out of Kong and into the data retention tool of your choice.</p>
          <p>Metrics are tracked for each node in a cluster as well as for the cluster as a whole. In Kong, a node is a running process with a unique identifier, configuration, cache layout, and connections to both Kong’s datastores and the upstream APIs it proxies. Note that node identifiers are unique to the process, and not to the host on which the process runs. In other words, each Kong restart results in a new node, and therefore a new node ID.</p>
          
          <h3>Request Counts</h3>
          <h4>Total Requests</h4>
          <p>This metric is the count of all API proxy requests received. This includes requests that were rejected due to rate-limiting, failed authentication, etc.</p>
          
          <h4>Requests Per Consumer</h4>
          <p>This metric is the count of all API proxy requests received from each specific consumer. Consumers are identified by credentials in their requests (e.g., API key, OAuth token, etc) as required by the Kong Auth plugin(s) in use.</p>
          
          <h3>Latency</h3>
          <p>Note: The Vitals API may return null for Latency metrics - this occurs when no API requests were proxied during the timeframe. Null latencies are not graphed in Kong’s Admin GUI - periods with null latencies will appear as a gap in Vitals charts.</p>
          
          <h4>Proxy Latency (Request)</h4>
          <p>These metrics are the min, max, and average values for the time, in milliseconds, that the Kong proxy spends processing API proxy requests. This includes time to execute plugins that run in the access phase as well as DNS lookup time. This does not include time spent in Kong’s load balancer, time spent sending the request to the upstream, or time spent on the response.</p>
          <p>Latency is not reported when a request is a prematurely ended by Kong (e.g., bad auth, rate limited, etc.) - note that this differs from the “Total Requests” metric that does count such requests.</p>
         
          <h4>Upstream Latency</h4>
          <p>These metrics are the min, max, and average values for the time elapsed, in milliseconds, between Kong sending requests upstream and Kong receiving the first bytes of responses from upstream.</p>
          
          <h3>Datastore Cache</h3>
          <p>Datastore Cache Hit/Miss<br>
          These metrics are the count of requests to Kong’s node-level datastore cache. When Kong workers need configuration information to respond to a given API proxy request, they first check their worker-specific cache (also known as L1 cache), then if the information isn’t available they check the node-wide datastore cache (also known as L2 cache). If neither cache contains the necessary information, Kong requests it from the datastore.</p>
          <p>A “Hit” indicates that an entity was retrieved from the data store cache. A “Miss” indicates that the record had to be fetched from the datastore. Not every API request will result in datastore cache access - some entities will be retrieved from Kong’s worker-specific cache memory.</p>
          
          <h4>Datastore Cache Hit Ratio</h4>
          <p>This metric contains the ratio of datastore cache hits to the total count of datastore cache requests.</p>
          
          <blockquote>
            <p>Note: Datastore Cache Hit Ratio cannot be calculated for time indices with no hits and no misses.</p>
          </blockquote>
          
          <h2>Vitals API</h2>
          <p>Vitals data is available via endpoints on Kong’s Admin API. Access to these endpoints may be controlled via Admin API RBAC. The Vitals API is described in the attached OAS (Open API Spec, formerly Swagger) file <a href="{{config.PORTAL_GUI_URL}}/documentation/files">vitals</a></p>
          
          <h2>Vitals Data Visualization in Kong Admin GUI</h2>
          <p>Kong’s Admin GUI includes visualization of Vitals data. Additional visualizations, dashboarding of Vitals data alongside data from other systems, etc., can be achieved using the Vitals API to integrate with common monitoring systems.</p>
          
          <h3>Time Frame Control</h3>
          <p>A time frame selector adjacent to Vitals charts in Kong’s Admin GUI controls the time frame of data visualized, which indirectly controls the granularity of the data. For example, the “Last 5 Minutes” choice will display 1-second resolution data, while longer time frames will show 1-minute resolution data.</p>
          <p>Timestamps on the x-axis of Vitals charts are displayed either in the browser’s local time zone, or in UTC, depending on the UTC option that appears adjacent to Vitals charts.</p>
          
          <h3>Cluster and Node Data</h3>
          <p>Metrics can be displayed on Vitals charts at both node and cluster level. Controls are available to show cluster-wide metrics and/or node-specific metrics. Clicking on individual nodes will toggle the display of data from those nodes. Nodes can be identified by a unique Kong node identifier, by hostname, or by a combination of the two.</p>
          
          <h2>Known Issues</h2>
          <p>Vitals data does not appear in the Admin UI or the API<br>
          First, make sure Vitals is enabled. (<code>vitals=on</code> in your Kong configuration).</p>
          <p>Then, check your log files. If you see <code>[vitals] kong_vitals_requests_consumers cache is full</code> or <code>[vitals] error attempting to push to list: no memory</code>, then Vitals is no longer able to track requests because its cache is full.  This condition may resolve itself if traffic to the node subsides long enough for it to work down the cache. Regardless, the node will continue to proxy requests as usual.</p>
          
          <h3>Limitations in Cassandra 2.x</h3>
          <p>Vitals data is purged regularly: 1-second data is purged after one hour, and 1-minute data is purged after 25 hours. Due to limitations in Cassandra 2.x query options, the counter table vitals_consumers is not purged. If it becomes necessary to prune this table, you will need to do so manually.</p>

        </section>
      </div>
    </div>
  {{/inline}}

{{/layout}}
]],
    auth = true
  },
  {
    type = "page",
    name = "guides/kong-architecture-overview",
    contents = [[{{#> layout pageTitle="Dev Portal - Kong EE Introduction" }}

  {{#* inline "content-block"}}
    <div class="app-container">
      <div class="container">
        {{> guides/sidebar}}

        <section class="page-wrapper kong-doc">
          <h1>Kong Architecture Overview</h1>
          <p>Broadly, Kong is suite of software that utilizes OpenResty to dynamically configure NGINX and process HTTP requests. This article covers the purpose and architecture of those underlying components as they relate to Kong’s execution.</p>
         
          <h2>NGINX</h2>
          <p>NGINX provides a robust HTTP server infrastructure. It handles HTTP request processing, TLS encryption, request logging, and allocation of operating system resources (e.g. listening for and managing client connections and spawning new processes).</p>

          <p>NGINX has a declarative configuration file that resides in its host operating system’s filesystem. While some Kong features (e.g. determining upstream request routing based on a request’s URL) are possible via NGINX configuration alone, modifying that configuration requires some level of operating system access to edit configuration files and to ask NGINX to reload them, whereas Kong allows users to update configuration via a RESTful HTTP API. <a href="https://github.com/Kong/kong/tree/master/kong/templates">Kong’s NGINX<br>
          configuration</a> is fairly basic: beyond configuring standard headers, listening ports, and log paths, most configuration is delegated to OpenResty.</p>

          <p>In some cases, it’s useful to add your own NGINX configuration alongside Kong’s, e.g. to serve a static website alongside your API gateway. In those cases, you can <a href="https://getkong.org/docs/latest/configuration/#custom-nginx-configuration">modify the configuration templates used by Kong</a>.</p>

          <p>Requests handled by NGINX pass through a sequence of <a href="https://nginx.org/en/docs/dev/development_guide.html#http_phases">phases</a>. Much of NGINX’s functionality (e.g. the <a href="http://nginx.org/en/docs/http/ngx_http_gzip_module.html">ability to use gzip compression</a> is provided by modules (written in C) that hook into these phases. While it is possible to write your own modules, NGINX must be recompiled every time a module is added or updated. To simplify the process of adding new functionality, Kong uses OpenResty.</p>
          
          <h2>OpenResty</h2>
          <p>OpenResty is a software suite that bundles NGINX, a set of modules, LuaJIT, and a set of Lua libraries. Chief among these is <code>ngx_http_lua_module</code>, an NGINX module which embeds Lua and provides Lua equivalents for most NGINX request phases. This effectively allows development of NGINX modules in Lua while maintaining high performance (LuaJIT is quite fast), and Kong uses it to provide its core configuration management and plugin management infrastructure.</p>
          
          <p>To understand how this is done, it helps to look at an abbreviated section of the Kong NGINX configuration:</p>
          
          <pre><code>upstream kong_upstream {
              server 0.0.0.1;
              balancer_by_lua_block {
                  kong.balancer()
              }
              keepalive ${{UPSTREAM_KEEPALIVE}};
          }

          server {
              server_name kong;
              listen ${{PROXY_LISTEN}}${{PROXY_PROTOCOL}};
              error_page 400 404 408 411 412 413 414 417 /kong_error_handler;
              error_page 500 502 503 504 /kong_error_handler;

              access_log ${{PROXY_ACCESS_LOG}};
              error_log ${{PROXY_ERROR_LOG}} ${{LOG_LEVEL}};
              ...
              location / {
                  set $upstream_host               '';
                  set $upstream_upgrade            '';
                  set $upstream_connection         '';
                  set $upstream_scheme             '';
                  set $upstream_uri                '';
                  set $upstream_x_forwarded_for    '';
                  set $upstream_x_forwarded_proto  '';
                  set $upstream_x_forwarded_host   '';
                  set $upstream_x_forwarded_port   '';

                  rewrite_by_lua_block {
                      kong.rewrite()
                  }

                  access_by_lua_block {
                      kong.access()
                  
                  }
                  ...
                  proxy_pass         $upstream_scheme://kong_upstream$upstream_uri;
                  ...
                </code></pre>
                
          <p>The above configuration first defines an upstream for later use. Typical configuration would specify an actual address for the upstream, but Kong instead uses the invalid placeholder address <code>0.0.0.1</code>, which will be overwritten by code executed in the <code>balancer_by_lua_block</code> section–Kong’s <code>balancer</code> function determines an appropriate address for upstream traffic based on the API and plugin configuration in Kong’s datastore.</p>
          
          <p>The remaining configuration sets up which addresses and ports NGINX listens on, defines log paths, and defines a location block. The location block indicates a URI prefix to apply configuration to–in this case, the prefix <code>/</code> simply matches all paths. After initializing NGINX variables for use later, it executes Kong’s <code>rewrite</code> and <code>access</code> functions in the appropriate OpenResty Lua blocks. The access phase, for example, corresponds to the <code>NGX_HTTP_ACCESS_PHASE</code> in an NGINX module, and is used to determine whether a client is allowed to make a request. As such, it’s appropriate for running authentication and access control code.</p>
          
          <p>Beyond running Lua code within NGINX, OpenResty provides modules that allow NGINX to communicate with a variety of database backends, including PostgreSQL and Apache Cassandra. These allow Kong to store and retrieve configurations in a more easily distributed fashion than is possible with flat files.</p>
          
          <h2>Kong</h2>
          <p>Kong provides a framework for hooking into the above request phases via its plugin architecture. Following from the example above, both the Key Auth and ACL plugins control whether a client (alternately called a consumer) should be able to make a request. Each defines its own access function in its handler, and that function is executed for each plugin enabled on a given route or service by <code>kong.access()</code>. Execution order is determined by a priority value–if Key Auth has priority 1003<br>
          and ACL has priority 950, Kong will execute Key Auth’s access function first and, if it does not drop the request, will then execute ACL’s before passing it upstream via <code>proxy_pass</code>.</p>
          
          <p>Because Kong’s request routing and handling configuration is controlled via its admin API, plugin configuration can be added and removed on on the fly without editing the underlying NGINX configuration, as Kong essentially provides a means to inject location blocks (via API definitions) and configuration within them (by assigning plugins, certificates, etc. to those APIs).</p>
          
          <h2>Summary</h2>
          <p>Kong’s overall infrastructure is composed of three main parts: NGINX provides protocol implementations and worker process management, OpenResty provides Lua integration and hooks into NGINX’s request processing phases, and Kong itself utilizes those hooks to route and transform requests.</p>
        </section>

      </div>
    </div>
  {{/inline}}
{{/layout}}
]],
    auth = true
  },
  {
    type = "spec",
    name = "vitals",
    contents = [[swagger: '2.0'
info:
  description: Vitals API
  version: 1.0.0
  title: Vitals API
host: 127.0.0.1:8001
basePath: /vitals
tags:
  - name: nodes
    description: Node level stats
  - name: cluster
    description: Cluster level stats
schemes:
  - http
paths:
  /:
    get:
      tags:
        - vitals
      summary: Get general information about Kong vitals
      description: ''
      operationId: getVitalsInfo
      produces:
        - application/json
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/VitalsInfo'
  /cluster:
    get:
      tags:
        - cluster
      summary: Get aggregated stats for the cluster
      description: ''
      operationId: getClusterStats
      produces:
        - application/json
      parameters:
        - name: interval
          in: query
          description: Interval length of requested stats
          required: true
          type: string
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/TimeSeriesWithMetadata'
        '400':
          description: Invalid query params
  /nodes:
    get:
      tags:
        - nodes
      summary: Get individual stats for all nodes
      description: ''
      operationId: getAllNodeStats
      produces:
        - application/json
      parameters:
        - name: interval
          in: query
          description: Interval length of requested stats
          required: true
          type: string
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/TimeSeriesWithMetadata'
        '400':
          description: Invalid query params
  '/nodes/{nodeUUID}':
    get:
      tags:
        - nodes
      summary: Get stats for a specific node by UUID
      description: ''
      operationId: getNodeStatsByUUID
      produces:
        - application/json
      parameters:
        - name: nodeUUID
          type: string
          in: path
          description: Node UUID to retrieve stats for
          required: true
        - name: interval
          in: query
          description: Interval length of requested stats
          required: true
          type: string
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/TimeSeriesWithMetadata'
        '400':
          description: Invalid query params
        '404':
          description: Unable to find requested node UUID
  '/consumers/{consumerUUID}/cluster':
    get:
      tags:
        - cluster
      summary: Get count of requests for the given consumer across entire cluster
      description: ''
      operationId: getConsumerClusterStats
      produces:
        - application/json
      parameters:
        - name: consumerUUID
          type: string
          in: path
          description: Consumer UUID to retrieve stats for
          required: true
        - name: interval
          type: string
          in: query
          description: Interval length of requested stats
          required: true
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/TimeSeriesWithMetadata'
        '400':
          description: Invalid query params
        '404':
          description: Unable to find requested consumer UUID
  '/consumers/{consumerUUID}/nodes':
    get:
      tags:
        - nodes
      summary: Get count of requests for the given consumer on each node
      description: ''
      operationId: getConsumerNodeStats
      produces:
        - application/json
      parameters:
        - name: consumerUUID
          type: string
          in: path
          description: Consumer UUID to retrieve stats for
          required: true
        - name: interval
          type: string
          in: query
          description: Interval length of requested stats
          required: true
      responses:
        '200':
          description: successful operation
          schema:
            $ref: '#/definitions/TimeSeriesWithMetadata'
        '400':
          description: Invalid query params
        '404':
          description: Unable to find requested consumer UUID
definitions:
  TimeSeriesWithMetadata:
    type: object
    properties:
      meta:
        properties:
          level:
            type: string
            example: cluster
            enum:
              - cluster
              - node
          interval:
            type: string
            example: seconds
            enum:
              - seconds
              - minutes
          earliest_ts:
            type: integer
            example: 1514508300
          latest_ts:
            type: integer
            example: 1514508480
          stat_labels:
            type: array
            items:
              type: string
            example:
              - cache_datastore_hits_total
              - cache_datastore_misses_total
              - latency_proxy_request_min_ms
              - latency_proxy_request_max_ms
              - latency_upstream_min_ms
              - latency_upstream_max_ms
              - requests_proxy_total
          nodes:
            type: object
            description: >-
              table of node ids that contributed to this time series. This
              element is not included on cluster-level requests.
            properties:
              <node_id>:
                type: object
                description: The id of a node included in this time series.
                properties:
                  hostname:
                    type: string
                    description: The name of the host where this node runs
      stats:
        properties:
          <node_id>:
            type: object
            description: >-
              The node this time series is for, or "cluster" if it's a
              cluster-level time series.
            properties:
              <timestamp_n>:
                type: array
                items:
                  type: integer
                description: >-
                  List of stat values collected at "timestamp_n", in same order
                  as "meta.stat_labels"
                example:
                  - 999
                  - 130
                  - 0
                  - 35
                  - 142
                  - 528
                  - 1146
  VitalsInfo:
    type: object
    example:
      stats:
        cache_datastore_hits_total:
          levels:
            cluster:
              intervals:
                minutes:
                  retention_period_seconds: 90000
                seconds:
                  retention_period_seconds: 3600
            nodes:
              intervals:
                minutes:
                  retention_period_seconds: 90000
                seconds:
                  retention_period_seconds: 3600
    properties:
      stats:
        type: object
        properties:
          <stat_label>:
            type: object
            properties:
              levels:
                type: object
                description: >-
                  Vitals data is tracked and aggregated at different levels (per
                  cluster, per node)
                properties:
                  cluster:
                    type: object
                    description: Vitals data available at the cluster level
                    properties:
                      intervals:
                        type: object
                        description: >-
                          Vitals data is available at different intervals
                          (seconds, minutes)
                        properties:
                          minutes:
                            type: object
                            properties:
                              retention_period_seconds:
                                type: integer
                                description: >-
                                  Configured retention period (in seconds) for
                                  the minutes interval
                          seconds:
                            type: object
                            properties:
                              retention_period_seconds:
                                type: integer
                                description: >-
                                  Configured retention period (in seconds) for
                                  the seconds interval
                  nodes:
                    type: object
                    description: Vitals data available at the node level
                    properties:
                      intervals:
                        type: object
                        description: >-
                          Vitals data is available at different intervals
                          (seconds, minutes)
                        properties:
                          minutes:
                            type: object
                            properties:
                              retention_period_seconds:
                                type: integer
                                description: >-
                                  Configured retention period (in seconds) for
                                  the minutes interval
                          seconds:
                            type: object
                            properties:
                              retention_period_seconds:
                                type: integer
                                description: >-
                                  Configured retention period (in seconds) for
                                  the seconds interval

]],
    auth = true
  },
  {
    type = "page",
    name = "dashboard",
    contents = [[{{#> layout pageTitle="Dashboard" }}

  {{#*inline "content-block"}}
    <div class="app-container">
      <div id="portal-dashboard" class="page-wrapper indent" page="dashboard"></div>
    </div>
  {{/inline}}

{{/layout}}
]],
    auth = true
  },
  {
    type = "page",
    name = "404",
    contents = [[{{#> layout pageTitle="404 - Page Not Found" }}

  {{#*inline "content-block"}}
    <div class="app-container error-page column">
      <h1>404</h1>
      <h2>Page not found</h2>
      <p>Sorry. We cannot find the page you were looking for.</p>
      <p>You could reload the page or go to the Homepage.</p>
      <a class="button button-primary" href="{{config.PORTAL_GUI_URL}}/">Go to Homepage</a>
    </div>
  {{/inline}}

{{/layout}}
]],
    auth = true
  },
  {
    type = "page",
    name = "guides/kong-ee-introduction",
    contents = [[{{#> layout pageTitle="Dev Portal - Kong EE Introduction" }}

  {{#* inline "content-block"}}
    <div class="app-container">
      <div class="container">
        {{> guides/sidebar}}
        <section class="page-wrapper kong-doc">
          <h1>Welcome to Kong Enterprise Edition</h1> 
          <p>Before going further into Kong Enterprise Edition (EE), make sure you understand its <a href="https://getkong.org/about/">purpose and philosophy</a>. Once you are confident with the concept of API Gateways, this guide is going to take you through a quick introduction on how to use Kong and perform basic operations such as:</p> 
          
          <ul> 
            <li>
              <a href="https://getkong.org/docs/enterprise/latest/getting-started/quickstart">Running your own Kong instance</a>.
            </li>
            <li>
              <a href="https://getkong.org/docs/enterprise/latest/getting-started/adding-your-api">Adding and consuming APIs</a>.
            </li>
            <li>
              <a href="https://getkong.org/docs/enterprise/latest/getting-started/enabling-plugins">Installing plugins on Kong</a>.
            </li>
          </ul> 
          
          <h3>What is Kong, technically?</h3> 
          <p>You’ve probably heard that Kong is built on NGINX, leveraging its stability and efficiency. But how is this possible exactly?</p> 
          <p>To be more precise, Kong is a Lua application running in NGINX and made possible by the <a href="https://github.com/openresty/lua-nginx-module">lua-nginx-module</a>. Instead of compiling NGINX with this module, Kong is distributed along with <a href="https://openresty.org/">OpenResty</a>, which already includes lua-nginx-module. OpenResty is <em>not</em> a fork of NGINX, but a bundle of modules extending its capabilities.</p> 
          
          <p>This sets the foundations for a pluggable architecture, where Lua scripts (referred to as <em>”Kong plugins”</em>) can be enabled and executed at runtime. Because of this, we like to think of Kong as <strong>a paragon of microservice architecture</strong>: at its core, it implements database abstraction, routing and plugin management. Plugins can live in separate code bases and be injected anywhere into the request lifecycle, all in a few lines of code.</p> 
          
          <h3>Next Steps</h3>
          <p>Now, lets get familiar with learning how to “start” and “stop” Kong EE.</p> 
          <p>Go to <a href="{{config.PORTAL_GUI_URL}}/guides/5-minute-quickstart">5-minute quickstart with Kong ›</a></p>
        </section>
      </div>
    </div>
  {{/inline}}

{{/layout}}
]],
    auth = true
  },
  {
    type = "partial",
    name = "header",
    contents = [[<header id="header">
  <div class="container">
    <div class="header-logo-container">
      <a class="logo" href="{{config.PORTAL_GUI_URL}}">
        <img alt="Welcome to the Developer Portal" src="data:image/png;base64,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"
        />
      </a>
    </div>
    <div class="header-content-container">
      <nav class="header-nav-container">
        <ul class="navigation">
          <li>
            <a href="{{config.PORTAL_GUI_URL}}/documentation">Documentation</a>
          </li>
          <li>
            <a href="{{config.PORTAL_GUI_URL}}/about">About</a>
          </li>
          <li>
            <a href="{{config.PORTAL_GUI_URL}}/guides">Guides</a>
          </li>
        </ul>
      </nav>
      {{> search/widget-vue }}
      {{> unauthenticated/login-actions auth=authData.authType}}
    </div>
    <div class="menu-trigger">
      <div class="bar"></div>
    </div>
  </div>
</header>
]],
    auth = true
  },
  {
    type = "partial",
    name = "unauthenticated/assets/base/alerts-css",
    contents = [[<style>
.alert {
  text-align: center;
  padding: 20px;
  border-radius: 5px;
}

.alert-info {
  border: 1px solid #ACD7FB;
  background-color: #EDF7FE;
  color: #557FA3;
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/layout/header-css",
    contents = [[<style>
#header {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  width: 100%;
  height: 80px;
  color: #fff;
  border-bottom: 1px solid rgba(255, 255, 255, 0.2);
  background: #001E33;
  z-index: 3;
}
#header .container {
  height: 100%;
  justify-content: space-between;
}
#header .header-content-container {
  display: flex;
  flex-direction: row;
  align-items: center;
  padding-right: 15px;
}
#header .menu-trigger {
  position: absolute;
  display: none;
  top: 35px;
  right: 1rem;
  width: 30px;
  height: 30px;
  color: #fff;
}
#header .menu-trigger .bar,
#header .menu-trigger .bar:after,
#header .menu-trigger .bar:before {
  width: 100%;
  height: 3px;
}
#header .menu-trigger .bar {
  position: relative;
  transform: translateY(5px);
  background: #fff;
  transition: all 0ms 300ms;
}
#header .menu-trigger .bar:before, #header .menu-trigger .bar:after {
  content: "";
  position: absolute;
  left: 0;
  background: #fff;
}
#header .menu-trigger .bar:before {
  bottom: 10px;
  transition: bottom 300ms 300ms cubic-bezier(0.23, 1, 0.32, 1), transform 300ms cubic-bezier(0.23, 1, 0.32, 1);
}
#header .menu-trigger .bar:after {
  top: 10px;
  transition: top 300ms 300ms cubic-bezier(0.23, 1, 0.32, 1), transform 300ms cubic-bezier(0.23, 1, 0.32, 1);
}
#header .menu-trigger.open .bar {
  background: rgba(255, 255, 255, 0);
}
#header .menu-trigger.open .bar:after {
  top: 0;
  transform: rotate(45deg);
  transition: top 300ms cubic-bezier(0.23, 1, 0.32, 1), transform 300ms 300ms cubic-bezier(0.23, 1, 0.32, 1);
}
#header .menu-trigger.open .bar:before {
  bottom: 0;
  transform: rotate(-45deg);
  transition: bottom 300ms cubic-bezier(0.23, 1, 0.32, 1), transform 300ms 300ms cubic-bezier(0.23, 1, 0.32, 1);
}
#header .header-logo-container {
  display: flex;
  flex: 1 1 auto;
  align-items: center;
  margin-left: 1rem;
}
#header .header-logo-container .logo {
  cursor: pointer;
}
#header .header-logo-container .logo img {
  width: 223px;
  height: auto;
  background-repeat: no-repeat;
}
#header nav.header-nav-container {
  display: flex;
  justify-content: right;
}
#header nav.header-nav-container > ul {
  list-style: none;
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0;
}
#header nav.header-nav-container > ul > li {
  margin: 0 0 0 1rem;
  flex: 1 auto;
  color: rgba(255, 255, 255, 0.8);
}
#header nav.header-nav-container > ul > li .dropdown-list {
  right: auto;
  left: auto;
}
#header nav.header-nav-container > ul > li:hover {
  color: white;
}
#header nav.header-nav-container > ul > li > a {
  display: block;
  padding: 0 10px 0 10px;
  text-decoration: none;
  line-height: 40px;
  color: rgba(255, 255, 255, 0.8);
}
#header nav.header-nav-container > ul > li > a:hover {
  color: white;
}
#header nav.header-nav-container > ul > li > a.button:hover {
  color: white;
}
#header nav.header-nav-container:not(:last-child) {
  flex: 1 1 auto;
}
#header nav.header-login-container {
  display: flex;
  flex: 1 1 auto;
  justify-content: flex-end;
  align-items: center;
  list-style-type: none;
  margin: 0 1rem;
}
#header nav.header-login-container > li:not(:last-child) {
  margin-right: 1rem;
}
#header nav.header-login-container > li:not(:last-child) > a {
  padding: 0 10px;
  color: rgba(255, 255, 255, 0.8);
}
#header nav.header-login-container > li:not(:last-child) > a:hover {
  color: white;
}
#header nav.header-login-container #logout {
  color: #C20A0A;
}
@media all and (max-width: 720px) {
  #header {
    position: fixed;
    top: 0;
    z-index: 10;
  }
  #header .menu-trigger {
    display: block;
  }
  #header nav .search-nav {
    display: none;
  }
  #header nav.header-nav-container {
    position: absolute;
    top: 80px;
    left: 0;
    width: 100%;
    height: auto;
    max-height: 0;
    overflow: hidden;
    background: #08273d;
    transition: max-height 500ms ease;
  }
  #header nav.header-nav-container.open {
    max-height: 100vh;
  }
  #header nav.header-nav-container.open:after {
    position: fixed;
    display: block;
    opacity: 0;
    right: 0;
    width: 100vw;
    height: 100vh;
    background: rgba(0, 0, 0, 0.45);
    animation: fadeIn 500ms ease 1 forwards;
    z-index: -1;
    content: "";
  }
  #header nav.header-nav-container ul {
    flex-direction: column;
    width: 100%;
  }
  #header nav.header-nav-container ul li {
    width: 100%;
    margin: 0;
    padding: 5px 0;
    text-align: center;
  }
  #header nav.header-login-container {
    display: inline;
    margin: 0;
  }
  #header nav.header-login-container > li:not(:last-child) {
    margin: 0;
    padding: 20px 0;
  }
  #header nav.header-login-container .dropdownWrapper {
    float: right;
    margin-right: 60px;
  }
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/base/base-css",
    contents = [[<style>
body, html {
  text-rendering: geometricPrecision;
  -webkit-font-smoothing: antialiased;
  color: #4d4d4d;
  height: 100%;
}

body {
  font-size: 16px;
  font-family: "Roboto", "Helvetica Neue", Arial, sans-serif;
  font-weight: 400;
}

a {
  color: #0086e6;
  text-decoration: none;
  transition: all 300ms ease;
}
a:hover {
  color: #4d4d4d;
}

.text-color.light {
  color: white;
}
.text-color.light-opaque {
  color: rgba(255, 255, 255, 0.7);
}
.text-color.dark {
  color: black;
}
.text-color.dark-opaque {
  color: rgba(0, 0, 0, 0.7);
}
.text-color.accent {
  color: #0077cc;
}
.text-color.dark-accent {
  color: #003459;
}

button,
.button {
  cursor: pointer;
  display: inline-block;
  font-weight: 400;
  line-height: 1.25;
  text-align: center;
  white-space: nowrap;
  vertical-align: middle;
  -webkit-user-select: none;
  -moz-user-select: none;
  -ms-user-select: none;
  user-select: none;
  border: 1px solid transparent;
  padding: 0.5rem 1rem;
  text-decoration: none;
  font-size: 1rem;
  border-radius: 0.25rem;
  -webkit-transition: all 0.2s ease-in-out;
  -o-transition: all 0.2s ease-in-out;
  transition: all 0.2s ease-in-out;
}
button.button-primary,
.button.button-primary {
  color: white;
  background-color: #0086e6;
}
button.button-primary:hover, button.button-primary:focus,
.button.button-primary:hover,
.button.button-primary:focus {
  background-color: #0068b3;
}
button.button-secondary,
.button.button-secondary {
  color: white;
  font-size: 0.9rem;
  background-color: #0086e6;
}
button.button-secondary:hover, button.button-secondary:focus,
.button.button-secondary:hover,
.button.button-secondary:focus {
  background-color: #0068b3;
}
button.button-outline,
.button.button-outline {
  font-size: 0.9rem;
  background-color: transparent;
  border: 1px solid #0086e6;
  color: #0086e6;
}
button.button-outline:hover, button.button-outline:focus,
.button.button-outline:hover,
.button.button-outline:focus {
  color: #0068b3;
  border: 1px solid #0068b3;
}
button.button-success,
.button.button-success {
  background-color: #4BA370;
  color: white;
}
button.button-success:hover,
.button.button-success:hover {
  background-color: #1AA354;
}
button.button-transparent,
.button.button-transparent {
  color: white;
  border-radius: 2px;
  font-weight: 500;
  background-color: rgba(255, 255, 255, 0.2);
}
button.button-transparent:hover,
.button.button-transparent:hover {
  background-color: rgba(255, 255, 255, 0.25);
}

.button-group .button:not(:first-child) {
  margin-left: 10px;
}

section {
  padding: 4rem;
}
@media all and (max-width: 720px) {
  section {
    padding: 2rem;
  }
}

.row {
  max-width: 1140px;
  width: 100%;
  margin: 0 auto;
}
.row .column {
  flex: 1;
}

.caret {
  position: relative;
  left: -20px;
  top: 0px;
}
.caret:before {
  content: "";
  position: absolute;
  top: 0;
  left: 0;
  border-left: 7px solid #4d4d4d;
  border-top: 7px solid transparent;
  border-bottom: 7px solid transparent;
}
.open .caret {
  top: 5px;
}
.open .caret:before {
  border-top: 7px solid #4d4d4d;
  border-left: 7px solid transparent;
  border-right: 7px solid transparent;
}

.kong-doc {
  max-width: 1200px;
}
.kong-doc p, .kong-doc ul, .kong-doc ol {
  line-height: 1.5;
  margin-top: 0;
}
.kong-doc ul, .kong-doc ol {
  padding-left: 20px;
}
.kong-doc ul img, .kong-doc ol img {
  margin: 0.5rem 0 1rem;
}
.kong-doc blockquote {
  opacity: 0.8;
  margin-left: 0;
  font-style: italic;
}
.kong-doc pre {
  max-width: 750px;
  background-color: #fafafa;
  border: 1px solid #ebebeb;
  color: #000;
  line-height: 24px;
  margin: 1.3em 0;
  padding: 12px 17px;
  border-radius: 4px;
}
.kong-doc pre code {
  display: block;
  padding: 0;
  color: #000;
  font-size: 14px;
  background: 0 0;
  border-radius: 3px;
  border: 0;
  margin: 0;
  white-space: pre;
  font-family: Consolas, liberation mono, Menlo, Courier, monospace;
}
.kong-doc code {
  padding: 4px;
  color: #eb3838;
  font-size: 14px;
  background-color: white;
  border-radius: 3px;
  border: 0;
  margin: 0;
  font-family: Consolas, liberation mono, Menlo, Courier, monospace;
}

#app {
  position: relative;
  display: flex;
  flex-direction: column;
  min-height: 100%;
}
#app.error h1 {
  padding: 1%;
  background-color: red;
  color: white;
}
#app.error pre {
  padding: 1%;
  font-size: 1.5rem;
}

.container, .app-container {
  display: flex;
  flex-direction: row;
  width: 100%;
  margin: 0 auto;
}
.container.--fluid, .--fluid.app-container {
  max-width: 100%;
}
.container.column, .column.app-container {
  flex-direction: column;
}
.container.expand, .expand.app-container {
  flex-grow: 1;
  flex-shrink: 0;
  flex-basis: auto;
}
.container.shrink, .shrink.app-container {
  flex-grow: 0;
  flex-shrink: 1;
  flex-basis: auto;
}

#app:empty {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
  width: 100%;
}

.app-container {
  max-width: 100%;
  padding-top: 80px;
  flex-direction: column;
  flex-grow: 1;
  flex-shrink: 0;
  flex-basis: auto;
}
[v-cloak] {
  display: none;
}
.page-wrapper {
  display: flex;
  flex-direction: column;
  position: relative;
  flex: 1;
}
.page-wrapper.indent {
  margin: 2% 5%;
}
.page-wrapper p {
  flex: 1 0 auto;
}


/**************************************************************************
 * swagger-ui container
 */
#ui-wrapper {
  display: flex;
  position: relative;
  flex: 1;
  min-height: 100vh;
  align-items: center;
  justify-content: center;
  font-size: 1.4rem;
  max-width: 100%;
}
#ui-wrapper.error {
  flex-direction: column;
  text-align: center;
}
@media all and (max-width: 720px) {
  #ui-wrapper {
    margin-top: 40px;
  }
}


/**************************************************************************
 * swagger-ui operation panel theming
 */
.swagger-ui .side-panel { background: hsl(220, 8%, 19%); }
.swagger-ui .model-example-wrapper { overflow: auto; }
.swagger-ui .code-block { background: hsla(220, 8%, 10%, 1); }
.swagger-ui .operations-container select { border-color: rgba(255,255,255,0.1); }


.overlay {
  position: fixed;
  display: none;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.45);
  z-index: 1;
}
.overlay.on {
  display: block;
}

@keyframes fadeIn {
  to {
    opacity: 1;
  }
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/layout/header-dropdown-css",
    contents = [[<style>
.dropdownWrapper {
  position: relative;
  cursor: pointer;
  margin-top: 5px;
}
.dropdownWrapper .header-text {
  display: flex;
  align-items: center;
  justify-content: center;
  line-height: 40px;
  height: 50px;
}
.dropdownWrapper .header-text .dropdown-arrow {
  margin-left: 0.5rem;
}
.dropdownWrapper .dropdown-list {
  display: none;
  position: absolute;
  right: 0;
  min-width: 175px;
  background-color: white;
  list-style-type: none;
  padding: 0;
  margin: 0;
  border-radius: 2px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
}
.dropdownWrapper .dropdown-list li {
  line-height: 30px;
  margin: 0;
  padding: 0.5rem 1rem;
}
.dropdownWrapper .dropdown-list li:hover {
  background-color: #EDF5FA;
}
.dropdownWrapper .dropdown-list li a {
  display: block;
  color: rgba(0, 0, 0, 0.7);
}
.dropdownWrapper:hover ul {
  display: block;
}
.dropdownWrapper .avatar {
  height: 36px;
  border-radius: 25px;
}

@media all and (max-width: 720px) {
  .header-nav-container .dropdownWrapper:not(.open):hover ul {
    display: none;
  }

  .header-nav-container .dropdownWrapper.open {
    width: 100%;
    text-align: center;
  }
  .header-nav-container .dropdownWrapper.open ul {
    display: block;
    position: relative;
    max-width: 100%;
    min-width: 100%;
    text-align: center;
    box-shadow: none;
    background: #001E33;
    padding: 0.5rem 0;
  }
  .header-nav-container .dropdownWrapper.open ul li a {
    color: white;
  }
  .header-nav-container .dropdownWrapper.open ul li:hover {
    background: none;
  }
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/auth-js",
    contents = [[{{#if auth}}
<script type="text/javascript">
  /*
  |-----------------------------------------------------------------------------
  | Authentication Javascript Hooks - customize different authentication events
  |-----------------------------------------------------------------------------
  |
  | Below are some functions that are called during different times
  | in the life-cycle of authentication. These functions can be
  | customized and extended, but it is not required.
  |
  */

  /*
   * When a user attempts to log in, but authentication fails.
   */
  function onLoginError(error) {
    var resp = error.response
    var errorMessages = {
    // 0: {
    //  status: 'approved',
    //  message: ""
    // },
      1: {
        status: 'requested',
        message: "You have requested access, but your account is pending approval."
      },
      2: {
        status: 'rejected',
        message: "This account has been rejected."
      },
      3: {
        status: 'revoked',
        message: "This account has been revoked."
      }
    }
    
    var errorMessage = errorMessages[resp.data.status] && errorMessages[resp.data.status].message || window.getMessageFromError(error)
    alert('Login failed. ' + errorMessage)
  }

  /* 
   * When a user attempts to register, but registration fails.
   */
  function onRegistrationError(error) {
    alert('Registration failed. ' + window.getMessageFromError(error))
  }

  /**
   * When a user registers successfully, you can customize
   * where they are redirected. By default, they are redirected
   * to the index route '/', PORTAL_GUI_URL
  */
  function onRegistrationSuccess() {
    alert('Thank you for registering! Your request will be reviewed.')
    window.navigateToHome() // Navigates to PORTAL_GUI_URL
  }
</script> {{/if}}
]],
    auth = false
  },
  {
    type = "page",
    name = "unauthenticated/index",
    contents = [[{{#> unauthenticated/layout pageTitle="Dev Portal"}}

  {{#* inline "content-block"}}
    <div class="app-container">
      <div id="homepage" class="container column expand">
        
        <section class="hero">
          <div class="row container">
            <div class="column">
              <h1 class="text-color light">Build with Kong</h1>
              <p class="text-color light-opaque">Kong can be even more powerful by integrating it with your platform, apps and services.</p>
              {{#if authData.authType}}
                <a href="{{config.PORTAL_GUI_URL}}/register" class="button button-success">Create a Developer Account</a>
              {{/if}}
            </div>
            <div class="column">
              <svg width="534px" height="364px" viewBox="0 0 534 364" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
                  <defs>
                      <linearGradient x1="8.71983782%" y1="6.72962816%" x2="69.7710641%" y2="75.4647943%" id="linearGradient-1">
                          <stop stop-color="#FFFFFF" stop-opacity="0" offset="0%"></stop>
                          <stop stop-color="#FFFFFF" stop-opacity="0.2" offset="100%"></stop>
                      </linearGradient>
                  </defs>
                  <g id="01-work-in-progress" stroke="none" stroke-width="1" fill="none" fill-rule="evenodd" opacity="0.400000006">
                      <g id="dev-portal--homepage" transform="translate(-746.000000, -166.000000)">
                          <g id="section--hero">
                              <g id="illustration" transform="translate(734.000000, 167.000000)">
                                  <polygon id="Fill-1" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="104.899666 215.044314 146.859532 236.024247 146.859532 194.064381 104.899666 173.084448"></polygon>
                                  <polygon id="Fill-3" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="188.819398 173.084448 188.819398 215.044314 146.859532 236.024247 146.859532 194.064381"></polygon>
                                  <polygon id="Fill-5" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="104.899666 173.084448 146.859532 152.104515 188.819398 173.084448 146.859532 194.064381"></polygon>
                                  <polygon id="Fill-17" fill="#FFFFFF" points="125.879599 183.574415 125.879599 204.554348 146.859532 215.044314 146.859532 194.064381"></polygon>
                                  <polygon id="Fill-19" fill="#FFFFFF" points="167.839465 183.574415 167.839465 204.554348 146.859532 215.044314 146.859532 194.064381"></polygon>
                                  <polygon id="Fill-21" fill="#FFFFFF" points="125.879599 183.574415 146.859532 173.084448 167.839465 183.574415 146.859532 194.064381"></polygon>
                                  <polygon id="Fill-63" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 236.024247 209.799331 257.004181 251.759197 277.984114 251.759197 257.004181"></polygon>
                                  <polygon id="Fill-65" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 236.024247 293.719064 257.004181 251.759197 277.984114 251.759197 257.004181"></polygon>
                                  <polygon id="Fill-67" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="209.799331 236.024247 251.759197 215.044314 293.719064 236.024247 251.759197 257.004181"></polygon>
                                  <polygon id="Fill-69" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 262.249164 209.799331 267.494147 251.759197 288.47408 251.759197 283.229097"></polygon>
                                  <polygon id="Fill-71" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 262.249164 293.719064 267.494147 251.759197 288.47408 251.759197 283.229097"></polygon>
                                  <polygon id="Fill-73" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 225.534281 209.799331 230.779264 251.759197 251.759197 251.759197 246.514214"></polygon>
                                  <polygon id="Fill-75" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 225.534281 293.719064 230.779264 251.759197 251.759197 251.759197 246.514214"></polygon>
                                  <polygon id="Fill-77" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="209.799331 225.534281 251.759197 204.554348 293.719064 225.534281 251.759197 246.514214"></polygon>
                                  <polygon id="Fill-79" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="251.759197 277.984114 215.044314 259.626672 209.799331 262.249164 251.759197 283.229097 293.719064 262.249164 288.47408 259.626672"></polygon>
                                  <polygon id="Fill-81" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 131.124582 209.799331 152.104515 251.759197 173.084448 251.759197 152.104515"></polygon>
                                  <polygon id="Fill-83" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 131.124582 293.719064 152.104515 251.759197 173.084448 251.759197 152.104515"></polygon>
                                  <polygon id="Fill-85" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="209.799331 131.124582 251.759197 110.144649 293.719064 131.124582 251.759197 152.104515"></polygon>
                                  <polygon id="Fill-87" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 157.349498 209.799331 162.594482 251.759197 183.574415 251.759197 178.329431"></polygon>
                                  <polygon id="Fill-89" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 157.349498 293.719064 162.594482 251.759197 183.574415 251.759197 178.329431"></polygon>
                                  <polygon id="Fill-91" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 120.634615 209.799331 125.879599 251.759197 146.859532 251.759197 141.614548"></polygon>
                                  <polygon id="Fill-93" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 120.634615 293.719064 125.879599 251.759197 146.859532 251.759197 141.614548"></polygon>
                                  <polygon id="Fill-95" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="209.799331 120.634615 251.759197 99.6546823 293.719064 120.634615 251.759197 141.614548"></polygon>
                                  <polygon id="Fill-97" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="251.759197 173.084448 215.044314 154.727007 209.799331 157.349498 251.759197 178.329431 293.719064 157.349498 288.47408 154.727007"></polygon>
                                  <polygon id="Fill-99" fill-opacity="0.2" fill="#FFFFFF" points="167.839465 194.064381 220.289298 220.289298 209.799331 225.534281 209.799331 236.024247 146.859532 204.554348"></polygon>
                                  <polygon id="Fill-101" fill-opacity="0.2" fill="#FFFFFF" points="283.229097 157.349498 314.698997 173.084448 314.698997 183.574415 314.698997 194.064381 262.249164 167.839465"></polygon>
                                  <polygon id="Fill-103" fill-opacity="0.2" fill="#FFFFFF" points="419.598662 246.514214 367.148829 220.289298 388.128763 209.799331 440.578595 236.024247"></polygon>
                                  <polygon id="Fill-105" fill-opacity="0.2" fill="#FFFFFF" points="377.638796 309.454013 283.229097 262.249164 262.249164 272.73913 356.658863 319.94398"></polygon>
                                  <path d="M68.7675585,165.508361 L0,131.124582 L20.9799331,120.634615 L89.7474916,155.018395 L184.157191,202.223244 L163.177258,212.713211 L68.7675585,165.508361 Z" id="Combined-Shape" fill="url(#linearGradient-1)"></path>
                                  <polygon id="Fill-107" fill-opacity="0.2" fill="#FFFFFF" points="241.269231 178.329431 220.289298 167.839465 188.819398 183.574415 188.819398 204.554348"></polygon>
                                  <polygon id="Fill-109" fill-opacity="0.2" fill="#FFFFFF" points="346.168896 220.289298 325.188963 209.799331 272.73913 236.024247 293.719064 246.514214"></polygon>
                                  <polygon id="Fill-111" fill-opacity="0.2" fill="#FFFFFF" points="493.028428 157.349498 472.048495 146.859532 388.128763 188.819398 398.618729 194.064381 398.618729 204.554348"></polygon>
                                  <polygon id="Fill-113" fill-opacity="0.2" fill="#FFFFFF" points="388.128763 104.899666 367.148829 94.409699 283.229097 136.369565 293.719064 141.614548 293.719064 152.104515"></polygon>
                                  <polygon id="Fill-115" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="356.658863 319.94398 356.658863 340.923913 398.618729 361.903846 398.618729 340.923913"></polygon>
                                  <polygon id="Fill-117" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="524.498328 277.984114 524.498328 298.964047 398.618729 361.903846 398.618729 340.923913"></polygon>
                                  <polygon id="Fill-119" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="356.658863 272.73913 356.658863 293.719064 398.618729 314.698997 398.618729 293.719064"></polygon>
                                  <polygon id="Fill-121" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="524.498328 230.779264 524.498328 251.759197 398.618729 314.698997 398.618729 293.719064"></polygon>
                                  <polygon id="Fill-123" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="356.658863 272.73913 482.538462 209.799331 524.498328 230.779264 398.618729 293.719064"></polygon>
                                  <polygon id="Fill-125" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="356.658863 309.454013 356.658863 314.698997 398.618729 335.67893 398.618729 330.433946"></polygon>
                                  <polygon id="Fill-127" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="524.498328 267.494147 524.498328 272.73913 398.618729 335.67893 398.618729 330.433946"></polygon>
                                  <polygon id="Fill-129" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="398.618729 325.188963 361.903846 306.831522 356.658863 309.454013 398.618729 330.433946 524.498328 267.494147 519.253344 264.871656"></polygon>
                                  <polygon id="Fill-131" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="356.658863 298.964047 356.658863 304.20903 398.618729 325.188963 398.618729 319.94398"></polygon>
                                  <polygon id="Fill-133" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="524.498328 257.004181 524.498328 262.249164 398.618729 325.188963 398.618729 319.94398"></polygon>
                                  <polygon id="Fill-135" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="398.618729 314.698997 361.903846 296.341555 356.658863 298.964047 398.618729 319.94398 524.498328 257.004181 519.253344 254.381689"></polygon>
                                  <polygon id="Fill-137" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="398.618729 335.67893 361.903846 317.321488 356.658863 319.94398 398.618729 340.923913 524.498328 277.984114 519.253344 275.361622"></polygon>
                                  <polygon id="Fill-139" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="314.698997 183.574415 314.698997 204.554348 356.658863 225.534281 356.658863 204.554348"></polygon>
                                  <polygon id="Fill-141" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="398.618729 183.574415 398.618729 204.554348 356.658863 225.534281 356.658863 204.554348"></polygon>
                                  <polygon id="Fill-143" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="314.698997 183.574415 356.658863 162.594482 398.618729 183.574415 356.658863 204.554348"></polygon>
                                  <polygon id="Fill-145" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="314.698997 209.799331 314.698997 215.044314 356.658863 236.024247 356.658863 230.779264"></polygon>
                                  <polygon id="Fill-147" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="398.618729 209.799331 398.618729 215.044314 356.658863 236.024247 356.658863 230.779264"></polygon>
                                  <polygon id="Fill-149" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="314.698997 173.084448 314.698997 178.329431 356.658863 199.309365 356.658863 194.064381"></polygon>
                                  <polygon id="Fill-151" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="398.618729 173.084448 398.618729 178.329431 356.658863 199.309365 356.658863 194.064381"></polygon>
                                  <polygon id="Fill-153" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="314.698997 173.084448 356.658863 152.104515 398.618729 173.084448 356.658863 194.064381"></polygon>
                                  <polygon id="Fill-155" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="356.658863 225.534281 319.94398 207.176839 314.698997 209.799331 356.658863 230.779264 398.618729 209.799331 393.373746 207.176839"></polygon>
                                  <g id="Group-3" transform="translate(356.658863, 20.979933)" fill="#FFFFFF" fill-opacity="0.4" stroke="#FFFFFF">
                                      <polygon id="Fill-7" points="0 47.2048495 0 68.1847826 146.859532 141.614548 146.859532 120.634615"></polygon>
                                      <polygon id="Fill-11" points="0 0 0 20.9799331 146.859532 94.409699 146.859532 73.4297659"></polygon>
                                      <polygon id="Fill-157" points="0 36.7148829 0 41.9598662 146.859532 115.389632 146.859532 110.144649"></polygon>
                                      <polygon id="Fill-163" points="0 26.2249164 0 31.4698997 146.859532 104.899666 146.859532 99.6546823"></polygon>
                                  </g>
                                  <g id="Group" transform="translate(503.518395, 73.429766)" fill="#FFFFFF" fill-opacity="0.2" stroke="#FFFFFF">
                                      <polygon id="Fill-9" points="41.9598662 68.1847826 0 89.1647157 0 68.1847826 41.9598662 47.2048495"></polygon>
                                      <polygon id="Fill-13" points="41.9598662 20.9799331 0 41.9598662 0 20.9799331 41.9598662 0"></polygon>
                                      <polygon id="Fill-159" points="41.9598662 41.9598662 0 62.9397993 0 57.6948161 41.9598662 36.7148829"></polygon>
                                      <polygon id="Fill-165" points="41.9598662 31.4698997 0 52.4498328 0 47.2048495 41.9598662 26.2249164"></polygon>
                                  </g>
                                  <g id="Group-2" transform="translate(356.658863, 0.000000)" fill="#FFFFFF" fill-opacity="0.6" stroke="#FFFFFF">
                                      <polygon id="Fill-15" points="188.819398 73.4297659 146.859532 94.409699 0 20.9799331 41.9598662 0"></polygon>
                                      <polygon id="Fill-161" points="188.819398 110.144649 183.574415 107.522157 146.859532 125.879599 5.24498328 55.0723244 0 57.6948161 146.859532 131.124582"></polygon>
                                      <polygon id="Fill-167" points="188.819398 99.6546823 183.574415 97.0321906 146.859532 115.389632 5.24498328 44.5823579 0 47.2048495 146.859532 120.634615"></polygon>
                                      <polygon id="Fill-169" points="188.819398 120.634615 183.574415 118.012124 146.859532 136.369565 5.24498328 65.562291 0 68.1847826 146.859532 141.614548"></polygon>
                                  </g>
                              </g>
                          </g>
                      </g>
                  </g>
              </svg>
            </div>
          </div>
        </section>
        
        <section class="catalog">
          <div class="row">
            <h2>API Catalog</h2>
            <p class="tagline">Manage the API Gateway, integrate the traffic &amp; consumption, manage your files.</p>
          </div>
          <div class="row container">
            <div class="catalog-item">
              <svg width="48" height="48">
                <path fill="#20B491" fill-rule="evenodd" d="M44.66439 31.5661295C45.419514 29.5043459 45.874872 27.2980407 45.977677 25h-8.012841c-.085085 1.2056011-.32282 2.3690567-.693993 3.4711566l7.393547 3.0949729zm-.773034 1.8445649l-7.393518-3.0949611c-.522697 1.032294-1.16953 1.9910749-1.920865 2.8567088l5.635892 5.6986237c1.4833-1.6162736 2.72806-3.454994 3.678491-5.4603714zM45.977677 23C45.46971 11.6453382 36.354654 2.5302846 25 2.0223227v8.0128414C31.934974 10.5245995 37.4754 16.065026 37.964836 23h8.012841zm2.001867 0H48v2h-.020456C47.455282 37.7910864 36.919851 48 24 48 10.745166 48 0 37.254834 0 24S10.745166 0 24 0c12.919851 0 23.455282 10.2089136 23.979544 22.9999916V23zm-9.184148 17.2819874l-5.633321-5.6960244C30.706628 36.7129967 27.503612 38 24 38c-7.731986 0-14-6.2680135-14-14 0-7.3957531 5.734724-13.4520895 13-13.9648359V2.0223227C11.313866 2.5451137 2 12.1848719 2 24c0 12.1502645 9.849736 22 22 22 5.696939 0 10.888125-2.1653908 14.795396-5.7180126zM24 36c6.627417 0 12-5.372583 12-12s-5.372583-12-12-12-12 5.372583-12 12 5.372583 12 12 12z"/>
              </svg>
              <h3>Vitals API</h3>
              <p>Monitor your Kong health and understand the microservice API transactions traversing Kong.</p>
              <p><a href="{{config.PORTAL_GUI_URL}}/documentation/vitals">Read the docs</a></p>
            </div>
            <div class="catalog-item">
             <svg width="49" height="44">
                <path fill="#67C6E6" fill-rule="evenodd" d="M46.004166 10V7c0-.5522847-.447715-1-1-1H22.236068c-1.136316 0-2.175106-.6420071-2.683282-1.6583592l-.894427-1.7888544C18.488967 2.2140024 18.142704 2 17.763932 2H3c-.552285 0-1 .4477153-1 1v5H0V3c0-1.6568542 1.343146-3 3-3h14.763932c1.136316 0 2.175106.6420071 2.683282 1.6583592l.894427 1.7888544C21.511033 3.7859976 21.857296 4 22.236068 4h22.768098c1.656855 0 3 1.3431458 3 3v3H48v32c0 1.1045695-.895431 2-2 2H2c-1.104569 0-2-.8954305-2-2V10h46.004166zM2 12v30h44V12H2zm17 8l4 6h-3v8h-2v-8h-3l4-6zm10 14l-4-6h3v-8h2v8h3l-4 6z"/>
              </svg>
              <h3>Files API</h3>
              <p>Manage your Developer Portal files and API Specifications.</p>
              <p><a href="{{config.PORTAL_GUI_URL}}/documentation/files">Read the docs</a></p>
            </div>
            <div class="catalog-item">
             <svg width="48" height="48">
                <path fill="#3F89D3" fill-rule="evenodd" d="M34 4h6v2c0 1.1045695.895431 2 2 2h2v6h3.5c.276142 0 .5.2238576.5.5v1c0 .2761424-.223858.5-.5.5H44v4h3.5c.276142 0 .5.2238576.5.5v1c0 .2761424-.223858.5-.5.5H44v4h3.5c.276142 0 .5.2238576.5.5v1c0 .2761424-.223858.5-.5.5H44v4h3.5c.276142 0 .5.2238576.5.5v1c0 .2761424-.223858.5-.5.5H44v6h-2c-1.104569 0-2 .8954305-2 2v2h-6v3.5c0 .2761424-.223858.5-.5.5h-1c-.276142 0-.5-.2238576-.5-.5V44h-4v3.5c0 .2761424-.223858.5-.5.5h-1c-.276142 0-.5-.2238576-.5-.5V44h-4v3.5c0 .2761424-.223858.5-.5.5h-1c-.276142 0-.5-.2238576-.5-.5V44h-4v3.5c0 .2761424-.223858.5-.5.5h-1c-.276142 0-.5-.2238576-.5-.5V44H8v-2c0-1.1045695-.895431-2-2-2H4v-6H.5c-.276142 0-.5-.2238576-.5-.5v-1c0-.2761424.223858-.5.5-.5H4v-4H.5c-.276142 0-.5-.2238576-.5-.5v-1c0-.2761424.223858-.5.5-.5H4v-4H.5c-.276142 0-.5-.2238576-.5-.5v-1c0-.2761424.223858-.5.5-.5H4v-4H.5c-.276142 0-.5-.2238576-.5-.5v-1c0-.2761424.223858-.5.5-.5H4V8h2c1.104569 0 2-.8954305 2-2V4h6V.5c0-.2761424.223858-.5.5-.5h1c.276142 0 .5.2238576.5.5V4h4V.5c0-.2761424.223858-.5.5-.5h1c.276142 0 .5.2238576.5.5V4h4V.5c0-.2761424.223858-.5.5-.5h1c.276142 0 .5.2238576.5.5V4h4V.5c0-.2761424.223858-.5.5-.5h1c.276142 0 .5.2238576.5.5V4zM10 6.0152588c0 2.209139-1.790861 4-4 4V38c2.209139 0 4 1.790861 4 4h28c0-2.209139 1.790861-4 4-4V10c-2.209139 0-4-1.790861-4-4H10v.0152588zM14 10h20c2.209139 0 4 1.790861 4 4v20c0 2.209139-1.790861 4-4 4H14c-2.209139 0-4-1.790861-4-4V14c0-2.209139 1.790861-4 4-4zm0 2c-1.104569 0-2 .8954305-2 2v20c0 1.1045695.895431 2 2 2h20c1.104569 0 2-.8954305 2-2V14c0-1.1045695-.895431-2-2-2H14z"/>
              </svg>
              <h3>Admin API</h3>
              <p>This API is designed for internal use and provides full control over Kong.</p>
              <p><a href="{{config.PORTAL_GUI_URL}}/documentation/admin">Read the docs</a></p>
            </div>
          </div>
        </section>

        <section class="getting-started">
          <div class="row">
            <h2>Getting Started</h2>
            <p class="tagline">Start building in no time with these Tutorials</p>
          </div>
          <div class="row container guides">
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p class="subtitle"><strong>5-Minutes guide to Kong EE</strong></p>
                <p>Learn the basics of Kong, make your first API Call.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/5-minute-quickstart/" target="_blank">Continue Reading &rsaquo;</a>
              </div>
            </div>
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p class="subtitle"><strong>Kong Architecture</strong></p>
                <p>Learn the purpose and architecture of Kongs underlying components.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/kong-architecture-overview/" target="_blank">Continue Reading &rsaquo;</a>
              </div>
            </div>
          </div>
          <div class="row container guides">
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p class="subtitle"><strong>Upload your first file via API</strong></p>
                <p>Create your own documentation with your own OAS File.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/uploading-spec" target="_blank">Continue Reading &rsaquo;</a>
              </div>
            </div>
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p class="subtitle"><strong>Vitals endpoints 101</strong></p>
                <p>Integrate data from Kong to your favorite monitoring tool.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/kong-vitals" target="_blank">Continue Reading &rsaquo;</a>
              </div>
            </div>
          </div>
        </section>

        <section class="footer column container expand">
          <h2 class="text-color light">Ready to Start Building?</h2>
          <p class="text-color light-opaque">View the product documentation to learn more about how to configure, <br>customize, add specs, and apply authentication to the Kong Developer Portal.</p>
          <a href="https://getkong.org/docs/enterprise/latest/developer-portal/introduction/">
            <button class="button button-success">
              View Dev Portal Documentation
            </button>
          </a>
        </section>

      </div>
    </div>
  {{/inline}}

{{/unauthenticated/layout}}
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/header",
    contents = [[<header id="header">
  <div class="container">
    <div class="header-logo-container">
      <a class="logo" href="{{config.PORTAL_GUI_URL}}">
        <img alt="Welcome to the Developer Portal" src="data:image/png;base64,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"
        />
      </a>
    </div>
    <nav class="header-nav-container">
      <ul class="navigation">
        <li>
          <a href="{{config.PORTAL_GUI_URL}}/about">About</a>
        </li>
        <li>
          <a href="{{config.PORTAL_GUI_URL}}/guides">Guides</a>
        </li>
        {{> unauthenticated/login-actions auth=authData.authType}}
      </ul>
    </nav>
  </div>
  <div class="menu-trigger">
    <div class="bar"></div>
  </div>
</header>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/layout/sidebar-css",
    contents = [[<style>
#sidebar .sidebar-menu {
  position: fixed;
  z-index: 2;
  top: 80px;
  width: 215px;
  height: calc(100vh - 80px);
  background: #fff;
  overflow-y: auto;
}
#sidebar #spec-sidebar {
  padding-bottom: 100px;
}
#sidebar .sidebar-list li.list-title {
  font-weight: 700;
  color: #003459;
  text-transform: uppercase;
}

.sidebar-list:not(.spec) {
  padding: 0 1.5rem;
  margin-top: 2rem;
}
.sidebar-list:not(.spec) ul {
  list-style-type: none;
  padding: 0;
  margin: 0;
}
.sidebar-list:not(.spec) ul li {
  padding: 0.5rem;
  font-size: 15px;
  font-weight: 400;
  color: rgba(0, 0, 0, 0.7);
  text-transform: capitalize;
}
.sidebar-list:not(.spec) ul li a {
  color: inherit;
}
.sidebar-list:not(.spec) ul li a:hover {
  color: black;
}
.sidebar-list:not(.spec) ul li.list-title {
  font-weight: 700;
  color: #003459;
  text-transform: uppercase;
}
.sidebar-list:not(.spec) ul li.submenu {
  margin-top: 1rem;
  margin-bottom: 1rem;
}
.sidebar-list:not(.spec) ul li.submenu.active ul {
  height: auto;
  max-height: 9999px;
}
.sidebar-list:not(.spec) ul li.submenu.active .submenu-title:after {
  transform: rotate(90deg);
}
.sidebar-list:not(.spec) ul li .submenu-title {
  position: relative;
  display: block;
  font-size: 15px;
  font-weight: 500;
  color: rgba(0, 0, 0, 0.85);
  cursor: pointer;
}
.sidebar-list:not(.spec) ul li .submenu-title:after {
  position: absolute;
  display: block;
  content: "";
  top: 2px;
  left: -1rem;
  width: 0;
  height: 0;
  border-top: 5px solid transparent;
  border-bottom: 5px solid transparent;
  border-left: 5px solid black;
}
.sidebar-list:not(.spec) ul li .submenu-items {
  max-height: 0;
  overflow: hidden;
}
.sidebar-list:not(.spec) ul li .submenu-items a {
  display: block;
  font-size: 14px;
  line-height: 1.2;
  font-weight: normal;
  color: rgba(0, 0, 0, 0.7);
}
.sidebar-list:not(.spec) ul li .submenu-items a:hover {
  color: black;
}
.sidebar-list:not(.spec) ul li .submenu-items li.active {
  background: rgba(0, 0, 0, 0.05);
}
.sidebar-list:not(.spec) ul li .submenu-items li.active a {
  font-weight: 500;
}
.sidebar-list:not(.spec) ul li .method:before {
  display: none;
  width: 47px;
  margin-right: 0.5rem;
  padding-top: 0.15rem;
  color: #fff;
  text-align: center;
  font-weight: normal;
  font-size: 11px;
  line-height: 1rem;
  border-radius: 2px;
  vertical-align: bottom;
}
.sidebar-list:not(.spec) ul li .method-post:before {
  content: "POST";
  background: #248FB2;
}
.sidebar-list:not(.spec) ul li .method-put:before {
  content: "PUT";
  background: #9B6F8A;
}
.sidebar-list:not(.spec) ul li .method-get:before {
  content: "GET";
  background: #6ABD5A;
}
.sidebar-list:not(.spec) ul li .method-delete:before {
  content: "DELETE";
  background: #E2797A;
}

@media all and (max-width: 1200px) {
  #sidebar {
    position: fixed;
    top: 40px;
    right: 0;
    transform: translateX(100%);
    transition: all 400ms ease;
    z-index: 2;
  }
  #sidebar.open {
    transform: translateX(0);
  }
  #sidebar.open .sidebar-menu {
    height: 100vh;
    width: auto;
    right: 0;
  }

  .sidebar-toggle {
    position: fixed;
    display: flex;
    top: 80px;
    left: 0;
    right: 0;
    width: 100%;
    height: 40px;
    align-items: center;
    justify-content: left;
    padding: 1rem;
    background: #eee;
    z-index: 2;
    transition: background 300ms ease;
    cursor: pointer;
  }
  .sidebar-toggle:hover {
    background: #f6f6f6;
  }
}

@media all and (min-width: 1201px) {
  .sidebar-toggle {
    display: none;
  }
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "search/widget-vue",
    contents = [[{{!-- imports --}}
{{> search/helpers-js }}

{{!-- template --}}
<div id="search">
  <div @click="toggleActive" id="search-icon" :class="{ active: searchActive }">
    {{> unauthenticated/assets/icons/search-header }}
  </div>
  <div id="search-window" :class="{ active: searchActive }">
    <div class="search-bar">
      <div v-if="isLoading">
        {{> unauthenticated/assets/icons/loading }}
      </div>
      <div v-else>
        {{> unauthenticated/assets/icons/search-widget }}
      </div>
      <input name="search"
        v-model="searchModel"
        @focus="toggleSearchFocus(true)"
        @blur="toggleSearchFocus(false)"
        placeholder="Search..."/>
    </div>
    <div class="search-item-container compact" v-if="!isLoading">
      <div class="search-row item"
        v-for="file in searchResults"
        @click="goToSearchResult(file.path)">
        <div class="item-inner">
          <p class="title">${ file.alias || file.title }</p>
          <p class="url">.../${ file.path }</p>
        </div>
      </div>
      <div class="search-row item" v-if="searchResults.length < 1 && searchModel !== ''">
        <div class="item-inner">
          <p>no results...</p>
        </div>
      </div>
      <div  @click="goToFullResults" class="search-row overflow" v-if="additionalResults > 0">
        <a>View ${ additionalResults } more results</a>
      </div>
    </div>
  </div>
</div>

{{!-- component --}}
<script>

window.registerApp(function () {
  new window.Vue({
    el: '#search',
    delimiters: ['${', '}'],

    data () {
      return {
        pageList: [],
        searchResults: [],
        additionalResults: 0,
        searchModel: '',
        searchActive: false,
        searchFocused: false,
        isLoading: false,

        fetchPageList: () => { console.log('error: fetchPageList helper failed to load') },
        searchFiles: () => { console.log('error: searchFiles helper failed to load') },
        goToPage: () => { console.log('error: goToPage helper failed to load') },
        buildUrl: () => { console.log('error: buildUrl helper failed to load') },
        isValidKey: () => { console.log('error: isValidKey helper failed to load') }
      }
    },

    created () {
      // event listener allowing user to type to search without having searchbar selected
      window.addEventListener('keyup', (event) => {
        // on escape close search window
        if (event.which === 27 && this.searchActive) {
          this.toggleActive()

        // on enter close if text box empty & go to results page if not
        } else if (this.searchActive && event.which === 13) {
          this.searchModel === '' ? this.toggleActive() : this.goToFullResults()

        // on delete remove last character of input model
        } else if (this.searchActive && !this.searchFocused && event.which === 8) {
          this.searchModel = this.searchModel.slice(0, this.searchModel.length - 1)

        // if key is character/special character append key event to input model
        } else if (this.searchActive && !this.searchFocused && this.isValidKey(event.which)) {
          this.searchModel += event.key
        }
      })

      // event listener allowing which closes search when clicked out of
      window.addEventListener('click', (event) => {
        let searchWindowEl = window.document.getElementById('search-window')
        let searchToggleEl = window.document.getElementById('search-icon')
        let isSearchWindowClicked = searchWindowEl.contains(event.target)
        let isSearchToggleClicked = searchToggleEl.contains(event.target)

        if (this.searchActive && !isSearchToggleClicked && !isSearchWindowClicked) {
          this.toggleActive()
        }
      })
    },

    mounted () {
      if (window.helpers) {
        this.fetchPageList = window.helpers.fetchPageList || this.fetchPageList
        this.searchFiles = window.helpers.searchFiles || this.searchFiles
        this.goToPage = window.helpers.goToPage || this.goToPage
        this.buildUrl = window.helpers.buildUrl || this.buildUrl
        this.isValidKey = window.helpers.isValidKey || this.isValidKey
      }
    },

    methods: {
      getFiles () {
        return window._kong.api.get('/files', { withCredentials: true })
      },

      goToFullResults () {
        let path = `search?query=${this.searchModel}`
        let url = this.buildUrl(path)
        this.goToPage(url)
      },

      goToSearchResult (path) {
        let url = this.buildUrl(path)
        this.goToPage(url)
      },

      toggleActive () {
        this.searchModel = ''
        this.searchActive = !this.searchActive
      },

      toggleSearchFocus (isFocused) {
        if (typeof isFocused === Boolean) {
          this.searchFocused = isFocused
          return
        }
        this.searchFocused = !this.searchFocused
      }
    },

    watch: {
      searchModel: {
        handler: function (searchModel, oldSearchModel) {
          if (!this.pageList.length && !this.isLoading) {
            this.isLoading = true
            this.getFiles().then((resp) => {
              this.pageList = this.fetchPageList(resp.data.data)
              let fullSearchResults = this.searchFiles(this.searchModel, this.pageList)
              this.searchResults = fullSearchResults.slice(0, 4)
              this.additionalResults = fullSearchResults.length - this.searchResults.length
              this.isLoading = false
            })
          } else {
            let fullSearchResults = this.searchFiles(this.searchModel, this.pageList)
            this.searchResults = fullSearchResults.slice(0, 4)
            this.additionalResults = fullSearchResults.length - this.searchResults.length
          }
        }
      }
    },

    beforeDestroy () {
      window.removeEventListener('keyup')
      window.removeEventListener('click')
    }
  })
})
</script>

{{!-- style --}}
<style>

#search {
  position: relative;
}

#search #search-icon {
  border-radius: 2px;
  cursor: pointer;
  height: 32px;
  width: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
}

#search #search-icon.active {
  background: rgba(0,0,0,0.30);
}

#search #search-icon svg {
  fill: #ffffff;
}

#search #search-window {
  position: absolute;
  max-width: 320px;
  padding: 0;
  border-radius: 3px;
  width: 320px;
  background-color: #ffffff;
  box-shadow: 0 2px 8px 0 rgba(0,0,0,0.24);
  left: -282px;
}

#search #search-window:not(.active) {
  display: none;
}

#search #search-window .search-bar {
  display: flex;
  flex-direction: row;
  align-items: center;
  margin: 0 24px;
}

#search #search-window .search-bar svg {
  fill: #8294A1;
  height: 18px;
  flex-grow: 1;
  flex-shrink: 0;
  display: flex;
}

#search #search-window input {
  text-align: left;
  flex-grow: 1;
  flex-shrink: 0;
  border: none;
  width: 100%;
  padding: 12px 0px 12px 8px;
  font-size: 16px;
  color: rgba(0,0,0,0.70);
  letter-spacing: 0;
}

#search #search-window input:focus {
  outline: none;
}

#search .search-header {
  width: 100%;
  border-bottom: 1px solid rgba(0,0,0,0.10);
  padding: 26px 32px;
  display: flex;
  align-content: center;
  align-items: center;
  justify-content: space-between;
}

#search .search-header h1 {
  font-size: 38px;
  color: rgba(0,0,0,0.85);
  letter-spacing: 0;
  text-align: left;
  line-height: 42.75px;
}

#search .search-row {
  cursor: pointer;
}

#search .search-row.item:hover {
  background-color: #EDF5FA
}

#search .search-row.overflow {
  margin: 0 24px;
  padding: 22px 0;
}

#search .search-row.overflow:hover a {
  text-decoration: underline;
}

#search .search-row .item-inner {
  border-bottom: 1px solid rgba(0,0,0,0.10);
  margin: 0 24px;
  padding: 22px 0;
}

#search .search-row:first-of-type .item-inner {
  border-top: 1px solid rgba(0,0,0,0.10);
}

#search .search-row.item .title {
  font-size: 16px;
  font-weight: 400px;
  text-decoration: none;
  margin: 0 0 10px;
  color: rgba(0,0,0,0.70);
  letter-spacing: 0;
  text-align: left;
}

#search .search-row.item p {
  font-size: 14px;
  margin: 0;
  color: rgba(0,0,0,0.45);
}

@media all and (max-width: 720px) {
  #search #search-window {
    position: fixed;
    width: 100%;
    max-width: 100%;
    border-radius: 0;
    right: 0;
    left: 0;
    top: 80px;
  }

  #search #search-window input {
    padding: 24px 0px 24px 8px;
  }
}
</style>
]],
    auth = true
  },
  {
    type = "partial",
    name = "search/results-vue",
    contents = [[{{!-- imports --}}
{{> search/helpers-js }}

{{!-- template --}}
<div id="search-results" :class="{ active: !isLoading }">
  <div class="search-header">
    <h1>${ searchResults.length } results for "${ searchModel }"</h1>
  </div>
  <div class="search-item-container expanded">
    <div class="search-row item"
      v-for="file in activeResults"
      @click="goToPage(file.path)">
      <h6 class="title">${ file.alias || file.title }</h6>
      <p class="url">${ buildUrl(file.path) }</p>
    </div>
  </div>
  <div class="pagination" v-if="searchResults.length > resultsPerPage">
    <button
      @click="rotatePagination(-1)"
      class="previous-item"
      :class="{ active: activePageIdx > 0 }">
      ${ "< Back" }
    </button>
    <button
      @click="goToPagination(idx)"
      class="pagination-item"
      :class="{ active: activePageIdx === idx }"
      v-for="item, idx in Object.keys(paginatedResults)">
      ${ idx + 1 }
    </button> 
    <button
      @click="rotatePagination(1)"
      class="next-item"
      :class="{ active: activePageIdx < activeResults.length }">
      ${ "Next >" }
    </button>
  </div>
</div>

{{!-- component --}}
<script>
window.registerApp(function () {

  new Vue({
    el: '#search-results',
    delimiters: ['${', '}'],

    data () {
      return {
        pageList: [],
        searchModel: '',
        searchResults: [],
        isLoading: true,

        paginatedResults: {},
        activeResults: [],
        activePageIdx: 0,
        resultsPerPage: 6,

        getUrlParameter: () => { console.log('error: getUrlParameter helper failed to load') },
        fetchPageList: () => { console.log('error: fetchPageList helper failed to load') },
        searchFiles: () => { console.log('error: searchFiles helper failed to load') },
        goToPage: () => { console.log('error: goToPage helper failed to load') },
        buildUrl: () => { console.log('error: buildUrl helper failed to load') }
      }
    },

    mounted () {
      if (window.helpers) {
        this.getUrlParameter = window.helpers.getUrlParameter || this.getUrlParameter
        this.fetchPageList = window.helpers.fetchPageList || this.fetchPageList
        this.searchFiles = window.helpers.searchFiles || this.searchFiles
        this.goToPage = window.helpers.goToPage || this.goToPage
        this.buildUrl = window.helpers.buildUrl || this.buildUrl
      }
      this.isLoading = true
      this.getFiles().then((resp) => {
        this.pageList = this.fetchPageList(resp.data.data)
        this.searchModel = this.getUrlParameter('query')
        this.searchResults = this.searchFiles(this.searchModel, this.pageList)
        this.paginatedResults = this.getPaginatedResults()
        this.activeResults = this.getActiveResults()
        this.isLoading = false
      })
    },

    methods: {
      getFiles () {
        return window._kong.api.get('/files', { withCredentials: true })
      },

      isPageActive (idx) {
        return this.activePageIdx === idx
      },

      toggleActive (isActive) {
        if (typeof isActive === Boolean) {
          this.searchActive = isActive
          return
        }
        this.searchActive = !this.searchActive
      },

      toggleSearchFocus (isFocused) {
        if (typeof isFocused === Boolean) {
          this.searchFocused = isFocused
          return
        }
        this.searchFocused = !this.searchFocused
      },

      goToPagination (idx) {
        this.activePageIdx = idx
      },

      rotatePagination (rotation) {
        let maxIdx = Object.keys(this.paginatedResults).length - 1
        let minIdx = 0

        if (rotation === 1 && (this.activePageIdx < maxIdx)) {
          this.activePageIdx += 1
        } else if (rotation === -1 && this.activePageIdx > minIdx) {
          this.activePageIdx -= 1
        }
      },

      getPaginatedResults () {
        let count = 0
        let pageIdx = 0
        let paginatedResults = {}

        if (!this.searchResults.length) {
          return { 0: [] }
        }

        for (pageIdx = 0; this.searchResults.length > count; pageIdx++) {
          paginatedResults[pageIdx] = []
          for (let k = 0; k < this.resultsPerPage; k++) {
            if (this.searchResults[count]) {
              paginatedResults[pageIdx].push(this.searchResults[count])
            }
            count += 1
          }
        }
        return paginatedResults
      },

      getActiveResults () {
        return this.paginatedResults[this.activePageIdx]
      }
    },

    watch: {
      activePageIdx: {
        handler: function() {
          this.activeResults = this.getActiveResults()
        }
      }
    }
  })
})
</script>

{{!-- style --}}
<style>

#search-results:not(.active) {
  display: none;
}

#search-results {
  padding: 0 183px;
}

#search-results .search-header {
  width: 100%;
  border-bottom: 1px solid rgba(0,0,0,0.10);
  padding: 26px 0;
  display: flex;
  align-content: center;
  align-items: center;
  justify-content: space-between;
}

#search-results .search-header input {
  border-width: 0;
  font-size: 16px;
  color: rgba(0,0,0,0.45);
  letter-spacing: 0;
  text-align: left;
  flex-grow: 1;
  flex-shrink: 0;
  flex-direction: row;
}

#search-results .pagination {
  display: flex;
  flex-direction: row;
  align-items: center;
  margin-top: 32px;
}

#search-results button:focus {
  outline: none;
}

#search-results .pagination-item {
  color: rgba(0, 0, 0, 0.45);
}

#search-results .pagination-item.active {
  color: rgba(0, 0, 0, 0.70);
}


#search-results .next-item, #search-results .previous-item {
  color: #B3B3B3;
  cursor: default;
}

#search-results .next-item.active, #search-results .previous-item.active {
  color: #0D93F2;
  cursor: pointer;
}

#search-results .search-header h1 {
  font-size: 38px;
  color: rgba(0,0,0,0.85);
  letter-spacing: 0;
  text-align: left;
  line-height: 42.75px;
}

#search-results .search-header svg {
  fill: #8294A1;
}

#search-results .search-row {
  padding: 22px 32px;
  cursor: pointer;
}

#search-results .search-row.item:hover {
  background-color: #EDF5FA
}

#search-results .search-row.overflow:hover a {
  text-decoration: underline;
}

#search-results .search-row.item {
  border-bottom: 1px solid rgba(0,0,0,0.10);
}

#search-results .search-row.item h6 {
  font-size: 16px;
  margin: 0 0 10px;
  color: rgba(0,0,0,0.70);
  letter-spacing: 0;
  text-align: left;
}

#search-results .search-row.item p {
  font-size: 14px;
  margin: 0;
  color: rgba(0,0,0,0.45);
}

@media all and (max-width: 720px) {
  #search-results {
    padding: 0 24px;
  }

  #search-results .search-header {
    padding: 26px 32px;
  }

  #search-results .search-header h1 {
    font-size: 24px;
  }
}

@media all and (max-width: 500px) {
  #search-results {
    padding: 0;
  }
}

</style>
]],
    auth = true
  },
  {
    type = "partial",
    name = "unauthenticated/assets/pages/login-css",
    contents = [[<style>
.authentication {
  margin: 208px auto;
  max-width: 365px;
  min-width: 300px;
  width: 100%;
}
.authentication * {
  display: block;
}
.authentication p * {
  display: initial;
}
.authentication .alert {
  margin: 10px 0 20px;
}
.authentication h1 {
  text-align: center;
}
.authentication button {
  width: 100%;
  margin-top: 1.5em;
}
.authentication .google-button-icon {
  display: inline-block;
  vertical-align: middle;
  margin: 5px 0 5px 5px;
  width: 18px;
  height: 18px;
}
.authentication .google-button-text {
  display: inline-block;
  vertical-align: middle;
  padding: 0 24px;
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/code-snippet-languages",
    contents = [[<script>
/*
|--------------------------------------------------------------------------
| Code snippet language selections for swagger ui.
|--------------------------------------------------------------------------
| 
*/
window.snippetLanguages = [
  {
    prismLanguage: 'javascript',
    target: 'javascript',
    client: 'xhr' // 'jquery', 
  },
  {
    prismLanguage: 'bash',
    target: 'shell',
    client: 'curl' // 'httpie', 'wget'
  },
  {
    prismLanguage: 'python',
    target: 'python'
  },
  {
    prismLanguage: 'ruby',
    target: 'ruby'
  }/*,
  {
    prismLanguage: 'php',
    target: 'php'
  },
  {
    prismLanguage: 'swift',
    target: 'swift'
  },
  {
    prismLanguage: 'java',
    target: 'java',
    client: 'unirest', 'okhttp'
  },
  {
    prismLanguage: 'ocaml',
    target: 'ocaml'
  },
  {
    prismLanguage: 'swift',
    target: 'swift'
  },
  {
    prismLanguage: 'csharp',
    target: 'csharp'
  },{
    prismLanguage: 'c',
    target: 'c'
  },{
    prismLanguage: 'javascript',
    target: 'node'
    //, client: // 'unirest', 'request', 'native'
  }*/
]
</script>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/pages/guides-css",
    contents = [[<style>
#guides .hero {
  display: flex;
  align-items: center;
  min-height: 15vh;
}
#guides .hero h1 {
  margin: 0;
  color: #00345a;
  font-size: 48px;
}
#guides .getting-started .guides {
  margin-bottom: 2rem;
}
#guides .getting-started .guides h2 {
  color: #00345a;
}
#guides .getting-started .guide {
  display: flex;
  margin: 0 1rem;
  padding-bottom: 1rem;
  border-top: 1px solid rgba(0, 0, 0, 0.1);
}
#guides .getting-started .guide:last-child {
  margin-right: 0;
}
@media all and (max-width: 720px) {
  #guides .getting-started .guide:last-child {
    margin-left: 0;
  }
}
#guides .getting-started .guide:first-child {
  margin-left: 0;
}
#guides .getting-started .guide .icon {
  padding: 1rem;
}
@media all and (max-width: 720px) {
  #guides .container {
    flex-direction: column;
  }
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "spec/sidebar",
    contents = [[<!-- Responsive sidebar toggle -->
<div class="sidebar-toggle">
  <p>Open Sidebar</p>
</div>

<!-- Sidebar -->
<div id="sidebar">
  <div class="sidebar-menu">
    <div class="sidebar-list">
      <ul>
        <li class="list-title">Getting Started</li>
        <li><a href="{{config.PORTAL_GUI_URL}}/guides">Introduction</a></li>
      </ul>
    </div>
    {{> spec/sidebar-list title="Resources" }}
  </div>
</div>
]],
    auth = true
  },
  {
    type = "partial",
    name = "unauthenticated/assets/base/fonts-css",
    contents = [[<style>
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/pages/404-css",
    contents = [[<style>
.error-page {
  height: 100vh;
  align-items: center;
  justify-content: center;
}
.error-page h1 {
  margin: 0;
  font-size: 72px;
  font-weight: 400;
  line-height: 80px;
  color: #8b8d8e;
}
.error-page h2 {
  font-size: 22px;
  font-weight: 500;
  line-height: 1.125;
}
.error-page p {
  margin: 2px;
}
.error-page p:last-of-type {
  margin-bottom: 1.2rem;
}

.unauthorized {
  margin: 208px auto;
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "spec/renderer",
    contents = [[<div id="ui-wrapper" data-spec="{{spec}}">
  Loading....
</div>
]],
    auth = true
  },
  {
    type = "page",
    name = "index",
    contents = [[{{#> layout pageTitle="Dev Portal"}}

  {{#* inline "content-block"}}
    <div class="app-container">
      <div id="homepage" class="container column expand">
        
        <section class="hero">
          <div class="row container">
            <div class="column">
              <h1 class="text-color light">Build with Kong</h1>
              <p class="text-color light-opaque">Kong can be even more powerful by integrating it with your platform, apps and services.</p>
              {{#if authData.authType}}
                <a href="{{config.PORTAL_GUI_URL}}/register" class="button button-success">Create a Developer Account</a>
              {{/if}}
            </div>
            <div class="column">
              <svg width="534px" height="364px" viewBox="0 0 534 364" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
                  <defs>
                      <linearGradient x1="8.71983782%" y1="6.72962816%" x2="69.7710641%" y2="75.4647943%" id="linearGradient-1">
                          <stop stop-color="#FFFFFF" stop-opacity="0" offset="0%"></stop>
                          <stop stop-color="#FFFFFF" stop-opacity="0.2" offset="100%"></stop>
                      </linearGradient>
                  </defs>
                  <g id="01-work-in-progress" stroke="none" stroke-width="1" fill="none" fill-rule="evenodd" opacity="0.400000006">
                      <g id="dev-portal--homepage" transform="translate(-746.000000, -166.000000)">
                          <g id="section--hero">
                              <g id="illustration" transform="translate(734.000000, 167.000000)">
                                  <polygon id="Fill-1" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="104.899666 215.044314 146.859532 236.024247 146.859532 194.064381 104.899666 173.084448"></polygon>
                                  <polygon id="Fill-3" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="188.819398 173.084448 188.819398 215.044314 146.859532 236.024247 146.859532 194.064381"></polygon>
                                  <polygon id="Fill-5" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="104.899666 173.084448 146.859532 152.104515 188.819398 173.084448 146.859532 194.064381"></polygon>
                                  <polygon id="Fill-17" fill="#FFFFFF" points="125.879599 183.574415 125.879599 204.554348 146.859532 215.044314 146.859532 194.064381"></polygon>
                                  <polygon id="Fill-19" fill="#FFFFFF" points="167.839465 183.574415 167.839465 204.554348 146.859532 215.044314 146.859532 194.064381"></polygon>
                                  <polygon id="Fill-21" fill="#FFFFFF" points="125.879599 183.574415 146.859532 173.084448 167.839465 183.574415 146.859532 194.064381"></polygon>
                                  <polygon id="Fill-63" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 236.024247 209.799331 257.004181 251.759197 277.984114 251.759197 257.004181"></polygon>
                                  <polygon id="Fill-65" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 236.024247 293.719064 257.004181 251.759197 277.984114 251.759197 257.004181"></polygon>
                                  <polygon id="Fill-67" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="209.799331 236.024247 251.759197 215.044314 293.719064 236.024247 251.759197 257.004181"></polygon>
                                  <polygon id="Fill-69" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 262.249164 209.799331 267.494147 251.759197 288.47408 251.759197 283.229097"></polygon>
                                  <polygon id="Fill-71" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 262.249164 293.719064 267.494147 251.759197 288.47408 251.759197 283.229097"></polygon>
                                  <polygon id="Fill-73" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 225.534281 209.799331 230.779264 251.759197 251.759197 251.759197 246.514214"></polygon>
                                  <polygon id="Fill-75" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 225.534281 293.719064 230.779264 251.759197 251.759197 251.759197 246.514214"></polygon>
                                  <polygon id="Fill-77" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="209.799331 225.534281 251.759197 204.554348 293.719064 225.534281 251.759197 246.514214"></polygon>
                                  <polygon id="Fill-79" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="251.759197 277.984114 215.044314 259.626672 209.799331 262.249164 251.759197 283.229097 293.719064 262.249164 288.47408 259.626672"></polygon>
                                  <polygon id="Fill-81" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 131.124582 209.799331 152.104515 251.759197 173.084448 251.759197 152.104515"></polygon>
                                  <polygon id="Fill-83" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 131.124582 293.719064 152.104515 251.759197 173.084448 251.759197 152.104515"></polygon>
                                  <polygon id="Fill-85" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="209.799331 131.124582 251.759197 110.144649 293.719064 131.124582 251.759197 152.104515"></polygon>
                                  <polygon id="Fill-87" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 157.349498 209.799331 162.594482 251.759197 183.574415 251.759197 178.329431"></polygon>
                                  <polygon id="Fill-89" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 157.349498 293.719064 162.594482 251.759197 183.574415 251.759197 178.329431"></polygon>
                                  <polygon id="Fill-91" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="209.799331 120.634615 209.799331 125.879599 251.759197 146.859532 251.759197 141.614548"></polygon>
                                  <polygon id="Fill-93" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="293.719064 120.634615 293.719064 125.879599 251.759197 146.859532 251.759197 141.614548"></polygon>
                                  <polygon id="Fill-95" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="209.799331 120.634615 251.759197 99.6546823 293.719064 120.634615 251.759197 141.614548"></polygon>
                                  <polygon id="Fill-97" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="251.759197 173.084448 215.044314 154.727007 209.799331 157.349498 251.759197 178.329431 293.719064 157.349498 288.47408 154.727007"></polygon>
                                  <polygon id="Fill-99" fill-opacity="0.2" fill="#FFFFFF" points="167.839465 194.064381 220.289298 220.289298 209.799331 225.534281 209.799331 236.024247 146.859532 204.554348"></polygon>
                                  <polygon id="Fill-101" fill-opacity="0.2" fill="#FFFFFF" points="283.229097 157.349498 314.698997 173.084448 314.698997 183.574415 314.698997 194.064381 262.249164 167.839465"></polygon>
                                  <polygon id="Fill-103" fill-opacity="0.2" fill="#FFFFFF" points="419.598662 246.514214 367.148829 220.289298 388.128763 209.799331 440.578595 236.024247"></polygon>
                                  <polygon id="Fill-105" fill-opacity="0.2" fill="#FFFFFF" points="377.638796 309.454013 283.229097 262.249164 262.249164 272.73913 356.658863 319.94398"></polygon>
                                  <path d="M68.7675585,165.508361 L0,131.124582 L20.9799331,120.634615 L89.7474916,155.018395 L184.157191,202.223244 L163.177258,212.713211 L68.7675585,165.508361 Z" id="Combined-Shape" fill="url(#linearGradient-1)"></path>
                                  <polygon id="Fill-107" fill-opacity="0.2" fill="#FFFFFF" points="241.269231 178.329431 220.289298 167.839465 188.819398 183.574415 188.819398 204.554348"></polygon>
                                  <polygon id="Fill-109" fill-opacity="0.2" fill="#FFFFFF" points="346.168896 220.289298 325.188963 209.799331 272.73913 236.024247 293.719064 246.514214"></polygon>
                                  <polygon id="Fill-111" fill-opacity="0.2" fill="#FFFFFF" points="493.028428 157.349498 472.048495 146.859532 388.128763 188.819398 398.618729 194.064381 398.618729 204.554348"></polygon>
                                  <polygon id="Fill-113" fill-opacity="0.2" fill="#FFFFFF" points="388.128763 104.899666 367.148829 94.409699 283.229097 136.369565 293.719064 141.614548 293.719064 152.104515"></polygon>
                                  <polygon id="Fill-115" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="356.658863 319.94398 356.658863 340.923913 398.618729 361.903846 398.618729 340.923913"></polygon>
                                  <polygon id="Fill-117" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="524.498328 277.984114 524.498328 298.964047 398.618729 361.903846 398.618729 340.923913"></polygon>
                                  <polygon id="Fill-119" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="356.658863 272.73913 356.658863 293.719064 398.618729 314.698997 398.618729 293.719064"></polygon>
                                  <polygon id="Fill-121" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="524.498328 230.779264 524.498328 251.759197 398.618729 314.698997 398.618729 293.719064"></polygon>
                                  <polygon id="Fill-123" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="356.658863 272.73913 482.538462 209.799331 524.498328 230.779264 398.618729 293.719064"></polygon>
                                  <polygon id="Fill-125" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="356.658863 309.454013 356.658863 314.698997 398.618729 335.67893 398.618729 330.433946"></polygon>
                                  <polygon id="Fill-127" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="524.498328 267.494147 524.498328 272.73913 398.618729 335.67893 398.618729 330.433946"></polygon>
                                  <polygon id="Fill-129" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="398.618729 325.188963 361.903846 306.831522 356.658863 309.454013 398.618729 330.433946 524.498328 267.494147 519.253344 264.871656"></polygon>
                                  <polygon id="Fill-131" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="356.658863 298.964047 356.658863 304.20903 398.618729 325.188963 398.618729 319.94398"></polygon>
                                  <polygon id="Fill-133" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="524.498328 257.004181 524.498328 262.249164 398.618729 325.188963 398.618729 319.94398"></polygon>
                                  <polygon id="Fill-135" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="398.618729 314.698997 361.903846 296.341555 356.658863 298.964047 398.618729 319.94398 524.498328 257.004181 519.253344 254.381689"></polygon>
                                  <polygon id="Fill-137" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="398.618729 335.67893 361.903846 317.321488 356.658863 319.94398 398.618729 340.923913 524.498328 277.984114 519.253344 275.361622"></polygon>
                                  <polygon id="Fill-139" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="314.698997 183.574415 314.698997 204.554348 356.658863 225.534281 356.658863 204.554348"></polygon>
                                  <polygon id="Fill-141" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="398.618729 183.574415 398.618729 204.554348 356.658863 225.534281 356.658863 204.554348"></polygon>
                                  <polygon id="Fill-143" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="314.698997 183.574415 356.658863 162.594482 398.618729 183.574415 356.658863 204.554348"></polygon>
                                  <polygon id="Fill-145" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="314.698997 209.799331 314.698997 215.044314 356.658863 236.024247 356.658863 230.779264"></polygon>
                                  <polygon id="Fill-147" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="398.618729 209.799331 398.618729 215.044314 356.658863 236.024247 356.658863 230.779264"></polygon>
                                  <polygon id="Fill-149" stroke="#FFFFFF" fill-opacity="0.4" fill="#FFFFFF" points="314.698997 173.084448 314.698997 178.329431 356.658863 199.309365 356.658863 194.064381"></polygon>
                                  <polygon id="Fill-151" stroke="#FFFFFF" fill-opacity="0.2" fill="#FFFFFF" points="398.618729 173.084448 398.618729 178.329431 356.658863 199.309365 356.658863 194.064381"></polygon>
                                  <polygon id="Fill-153" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="314.698997 173.084448 356.658863 152.104515 398.618729 173.084448 356.658863 194.064381"></polygon>
                                  <polygon id="Fill-155" stroke="#FFFFFF" fill-opacity="0.6" fill="#FFFFFF" points="356.658863 225.534281 319.94398 207.176839 314.698997 209.799331 356.658863 230.779264 398.618729 209.799331 393.373746 207.176839"></polygon>
                                  <g id="Group-3" transform="translate(356.658863, 20.979933)" fill="#FFFFFF" fill-opacity="0.4" stroke="#FFFFFF">
                                      <polygon id="Fill-7" points="0 47.2048495 0 68.1847826 146.859532 141.614548 146.859532 120.634615"></polygon>
                                      <polygon id="Fill-11" points="0 0 0 20.9799331 146.859532 94.409699 146.859532 73.4297659"></polygon>
                                      <polygon id="Fill-157" points="0 36.7148829 0 41.9598662 146.859532 115.389632 146.859532 110.144649"></polygon>
                                      <polygon id="Fill-163" points="0 26.2249164 0 31.4698997 146.859532 104.899666 146.859532 99.6546823"></polygon>
                                  </g>
                                  <g id="Group" transform="translate(503.518395, 73.429766)" fill="#FFFFFF" fill-opacity="0.2" stroke="#FFFFFF">
                                      <polygon id="Fill-9" points="41.9598662 68.1847826 0 89.1647157 0 68.1847826 41.9598662 47.2048495"></polygon>
                                      <polygon id="Fill-13" points="41.9598662 20.9799331 0 41.9598662 0 20.9799331 41.9598662 0"></polygon>
                                      <polygon id="Fill-159" points="41.9598662 41.9598662 0 62.9397993 0 57.6948161 41.9598662 36.7148829"></polygon>
                                      <polygon id="Fill-165" points="41.9598662 31.4698997 0 52.4498328 0 47.2048495 41.9598662 26.2249164"></polygon>
                                  </g>
                                  <g id="Group-2" transform="translate(356.658863, 0.000000)" fill="#FFFFFF" fill-opacity="0.6" stroke="#FFFFFF">
                                      <polygon id="Fill-15" points="188.819398 73.4297659 146.859532 94.409699 0 20.9799331 41.9598662 0"></polygon>
                                      <polygon id="Fill-161" points="188.819398 110.144649 183.574415 107.522157 146.859532 125.879599 5.24498328 55.0723244 0 57.6948161 146.859532 131.124582"></polygon>
                                      <polygon id="Fill-167" points="188.819398 99.6546823 183.574415 97.0321906 146.859532 115.389632 5.24498328 44.5823579 0 47.2048495 146.859532 120.634615"></polygon>
                                      <polygon id="Fill-169" points="188.819398 120.634615 183.574415 118.012124 146.859532 136.369565 5.24498328 65.562291 0 68.1847826 146.859532 141.614548"></polygon>
                                  </g>
                              </g>
                          </g>
                      </g>
                  </g>
              </svg>
            </div>
          </div>
        </section>
        
        <section class="catalog">
          <div class="row">
            <h2>API Catalog</h2>
            <p class="tagline">Manage the API Gateway, integrate the traffic &amp; consumption, manage your files.</p>
          </div>
          <div class="row container">
            <div class="catalog-item">
              <svg width="48" height="48">
                <path fill="#20B491" fill-rule="evenodd" d="M44.66439 31.5661295C45.419514 29.5043459 45.874872 27.2980407 45.977677 25h-8.012841c-.085085 1.2056011-.32282 2.3690567-.693993 3.4711566l7.393547 3.0949729zm-.773034 1.8445649l-7.393518-3.0949611c-.522697 1.032294-1.16953 1.9910749-1.920865 2.8567088l5.635892 5.6986237c1.4833-1.6162736 2.72806-3.454994 3.678491-5.4603714zM45.977677 23C45.46971 11.6453382 36.354654 2.5302846 25 2.0223227v8.0128414C31.934974 10.5245995 37.4754 16.065026 37.964836 23h8.012841zm2.001867 0H48v2h-.020456C47.455282 37.7910864 36.919851 48 24 48 10.745166 48 0 37.254834 0 24S10.745166 0 24 0c12.919851 0 23.455282 10.2089136 23.979544 22.9999916V23zm-9.184148 17.2819874l-5.633321-5.6960244C30.706628 36.7129967 27.503612 38 24 38c-7.731986 0-14-6.2680135-14-14 0-7.3957531 5.734724-13.4520895 13-13.9648359V2.0223227C11.313866 2.5451137 2 12.1848719 2 24c0 12.1502645 9.849736 22 22 22 5.696939 0 10.888125-2.1653908 14.795396-5.7180126zM24 36c6.627417 0 12-5.372583 12-12s-5.372583-12-12-12-12 5.372583-12 12 5.372583 12 12 12z"/>
              </svg>
              <h3>Vitals API</h3>
              <p>Monitor your Kong health and understand the microservice API transactions traversing Kong.</p>
              <p><a href="{{config.PORTAL_GUI_URL}}/documentation/vitals">Read the docs</a></p>
            </div>
            <div class="catalog-item">
             <svg width="49" height="44">
                <path fill="#67C6E6" fill-rule="evenodd" d="M46.004166 10V7c0-.5522847-.447715-1-1-1H22.236068c-1.136316 0-2.175106-.6420071-2.683282-1.6583592l-.894427-1.7888544C18.488967 2.2140024 18.142704 2 17.763932 2H3c-.552285 0-1 .4477153-1 1v5H0V3c0-1.6568542 1.343146-3 3-3h14.763932c1.136316 0 2.175106.6420071 2.683282 1.6583592l.894427 1.7888544C21.511033 3.7859976 21.857296 4 22.236068 4h22.768098c1.656855 0 3 1.3431458 3 3v3H48v32c0 1.1045695-.895431 2-2 2H2c-1.104569 0-2-.8954305-2-2V10h46.004166zM2 12v30h44V12H2zm17 8l4 6h-3v8h-2v-8h-3l4-6zm10 14l-4-6h3v-8h2v8h3l-4 6z"/>
              </svg>
              <h3>Files API</h3>
              <p>Manage your Developer Portal files and API Specifications.</p>
              <p><a href="{{config.PORTAL_GUI_URL}}/documentation/files">Read the docs</a></p>
            </div>
            <div class="catalog-item">
             <svg width="48" height="48">
                <path fill="#3F89D3" fill-rule="evenodd" d="M34 4h6v2c0 1.1045695.895431 2 2 2h2v6h3.5c.276142 0 .5.2238576.5.5v1c0 .2761424-.223858.5-.5.5H44v4h3.5c.276142 0 .5.2238576.5.5v1c0 .2761424-.223858.5-.5.5H44v4h3.5c.276142 0 .5.2238576.5.5v1c0 .2761424-.223858.5-.5.5H44v4h3.5c.276142 0 .5.2238576.5.5v1c0 .2761424-.223858.5-.5.5H44v6h-2c-1.104569 0-2 .8954305-2 2v2h-6v3.5c0 .2761424-.223858.5-.5.5h-1c-.276142 0-.5-.2238576-.5-.5V44h-4v3.5c0 .2761424-.223858.5-.5.5h-1c-.276142 0-.5-.2238576-.5-.5V44h-4v3.5c0 .2761424-.223858.5-.5.5h-1c-.276142 0-.5-.2238576-.5-.5V44h-4v3.5c0 .2761424-.223858.5-.5.5h-1c-.276142 0-.5-.2238576-.5-.5V44H8v-2c0-1.1045695-.895431-2-2-2H4v-6H.5c-.276142 0-.5-.2238576-.5-.5v-1c0-.2761424.223858-.5.5-.5H4v-4H.5c-.276142 0-.5-.2238576-.5-.5v-1c0-.2761424.223858-.5.5-.5H4v-4H.5c-.276142 0-.5-.2238576-.5-.5v-1c0-.2761424.223858-.5.5-.5H4v-4H.5c-.276142 0-.5-.2238576-.5-.5v-1c0-.2761424.223858-.5.5-.5H4V8h2c1.104569 0 2-.8954305 2-2V4h6V.5c0-.2761424.223858-.5.5-.5h1c.276142 0 .5.2238576.5.5V4h4V.5c0-.2761424.223858-.5.5-.5h1c.276142 0 .5.2238576.5.5V4h4V.5c0-.2761424.223858-.5.5-.5h1c.276142 0 .5.2238576.5.5V4h4V.5c0-.2761424.223858-.5.5-.5h1c.276142 0 .5.2238576.5.5V4zM10 6.0152588c0 2.209139-1.790861 4-4 4V38c2.209139 0 4 1.790861 4 4h28c0-2.209139 1.790861-4 4-4V10c-2.209139 0-4-1.790861-4-4H10v.0152588zM14 10h20c2.209139 0 4 1.790861 4 4v20c0 2.209139-1.790861 4-4 4H14c-2.209139 0-4-1.790861-4-4V14c0-2.209139 1.790861-4 4-4zm0 2c-1.104569 0-2 .8954305-2 2v20c0 1.1045695.895431 2 2 2h20c1.104569 0 2-.8954305 2-2V14c0-1.1045695-.895431-2-2-2H14z"/>
              </svg>
              <h3>Admin API</h3>
              <p>This API is designed for internal use and provides full control over Kong.</p>
              <p><a href="{{config.PORTAL_GUI_URL}}/documentation/admin">Read the docs</a></p>
            </div>
          </div>
        </section>

        <section class="getting-started">
          <div class="row">
            <h2>Getting Started</h2>
            <p class="tagline">Start building in no time with these Tutorials</p>
          </div>
          <div class="row container guides">
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p class="subtitle"><strong>5-Minutes guide to Kong EE</strong></p>
                <p>Learn the basics of Kong, make your first API Call.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/5-minute-quickstart/" target="_blank">Continue Reading &rsaquo;</a>
              </div>
            </div>
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p class="subtitle"><strong>Kong Architecture</strong></p>
                <p>Learn the purpose and architecture of Kongs underlying components.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/kong-architecture-overview/" target="_blank">Continue Reading &rsaquo;</a>
              </div>
            </div>
          </div>
          <div class="row container guides">
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p class="subtitle"><strong>Upload your first file via API</strong></p>
                <p>Create your own documentation with your own OAS File.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/uploading-spec" target="_blank">Continue Reading &rsaquo;</a>
              </div>
            </div>
            <div class="column guide">
              <div class="icon">
                <svg width="32" height="32" viewBox="0 0 32 32">
                  <g fill="none" fill-rule="evenodd">
                    <path fill="#FFF" fill-opacity=".1" d="M0 0h32v32H0z"/>
                    <path fill="#ADBFCC" d="M29 9v21c0 1.1045695-.8954305 2-2 2H5c-1.1045695 0-2-.8954305-2-2V2c0-1.1045695.8954305-2 2-2h15l9 9zm-10 1h8l-8-8v8zm-2-8H5v28h22V12H17V2zM8.5 5h6c.2761424 0 .5.22385763.5.5v1c0 .27614237-.2238576.5-.5.5h-6c-.27614237 0-.5-.22385763-.5-.5v-1c0-.27614237.22385763-.5.5-.5zm0 5h6c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-6c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h15c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-15c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5zm0 5h11c.2761424 0 .5.2238576.5.5v1c0 .2761424-.2238576.5-.5.5h-11c-.27614237 0-.5-.2238576-.5-.5v-1c0-.2761424.22385763-.5.5-.5z"/>
                  </g>
                </svg>
              </div>
              <div class="text">
                <p class="subtitle"><strong>Vitals endpoints 101</strong></p>
                <p>Integrate data from Kong to your favorite monitoring tool.</p>
                <a href="{{config.PORTAL_GUI_URL}}/guides/kong-vitals" target="_blank">Continue Reading &rsaquo;</a>
              </div>
            </div>
          </div>
        </section>

        <section class="footer column container expand">
          <h2 class="text-color light">Ready to Start Building?</h2>
          <p class="text-color light-opaque">View the product documentation to learn more about how to configure, <br>customize, add specs, and apply authentication to the Kong Developer Portal.</p>
          <a href="https://getkong.org/docs/enterprise/latest/developer-portal/introduction/">
            <button class="button button-success">
              View Dev Portal Documentation
            </button>
          </a>
        </section>

      </div>
    </div>
  {{/inline}}

{{/layout}}
]],
    auth = true
  },
  {
    type = "partial",
    name = "spec/sidebar-list",
    contents = [[{{!-- imports --}}
{{> spec/helpers-js }}

{{!-- template --}}
<div class="spec sidebar-list" id="spec-sidebar-list" v-if="sidebarData.length">
  <ul :class="{ active: !isLoading }">
    <li class="list-title">Resources</li>
    <li 
      v-for="sidebarItem in sidebarData"
      class="submenu"
      :class="{ active: isTagActive(sidebarItem.tag) }">
      <span class="submenu-title" @click="subMenuClicked(sidebarItem)">${ sidebarItem.tag }</span>
      <ul class="submenu-items">
        <div v-for="path in sidebarItem.paths">
          <div v-for="method in path.methods">
            <li class="method" :class="{ active: isIdActive(method.id) }">
              <a
                @click="sidebarAnchorClicked(sidebarItem, method)">
                ${method.summary}
              </a>
            </li>
          </div>
        </div>
      </ul>
    </li>
  </ul>
</div>

{{!-- component --}}
<script>

window.registerApp(function () {
  new window.Vue({
    el: '#spec-sidebar-list',
    delimiters: ['${', '}'],

    data () {
      return {
        specName: window._kong.spec.name,
        spec: window._kong.spec,
        sidebarData: [],
        activeTags: [],
        activeId: null,
        isLoading: true,

        buildSidebar: () => { console.log('error: buildSidebar helper failed to load') },
        retrieveParsedSpec: () => { console.log('error: retrieveParsedSpec helper failed to load') }
      }
    },

    mounted () {
      if (window.helpers) {
        this.buildSidebar = window.helpers.buildSidebar || this.buildSidebar
        this.retrieveParsedSpec = window.helpers.retrieveParsedSpec || this.retrieveParsedSpec
        let spec = this.retrieveParsedSpec(this.specName, this.spec)
        let builtSpec = this.buildSidebar(spec)
        this.sidebarData = builtSpec
        this.isLoading = false
      }
    },

    methods: {
      moveToAnchor (destination) {
        window.scrollTo(0, destination.offsetTop - 120)
      },

      isIdActive (id) {
        return this.activeId === id
      },

      isTagActive (tag) {
        return this.activeTags.includes(tag)
      },

      sidebarAnchorClicked (sidebarItem, method) {
        this.activeTags.push(sidebarItem.tag)
        this.activeId = method.id
        let anchorPath = `operations-${sidebarItem.tag}-${method.id}`
        window.location.hash = anchorPath
        let anchor = document.querySelector(`#${anchorPath}`)
        this.moveToAnchor(anchor)
      },

      subMenuClicked (sidebarItem) {
        if (this.isTagActive(sidebarItem.tag)) {
          this.activeTags = this.activeTags.filter(activeTag => activeTag !== sidebarItem.tag)
          return 
        }
        this.activeTags.push(sidebarItem.tag)
      }
    }
  })
})
</script>

{{!-- style --}}
<style>
  #spec-sidebar-list > ul:not(.active) {
    display: none;
  }

  #spec-sidebar-list .method a {
    cursor: pointer;
  }

  #spec-sidebar-list {
    padding: 0 1.5rem;
    margin-top: 2rem;
  }

  #spec-sidebar-list ul {
    list-style-type: none;
    padding: 0;
    margin: 0;
  }

  #spec-sidebar-list ul li {
    padding: .5rem;
    font-size: 15px;
    font-weight: 400;
    color: rgba(0,0,0,.7);
    text-transform: capitalize;
  }

  #spec-sidebar-list ul li a {
    color: inherit;
  }

  #spec-sidebar-list ul li a:hover {
    color: black;
  }

  #spec-sidebar-list ul.list-title {
    font-weight: 700;
    color: rgba(0, 52, 89, 1);
    text-transform: uppercase;
  }

  #spec-sidebar-list ul.submenu {
    margin-top: 1rem;
    margin-bottom: 1rem;
  }

  #spec-sidebar-list ul li.submenu.active ul {
    height: auto;
    max-height: 9999px;
  }

  #spec-sidebar-list ul li .submenu.active .submenu-title:after {
    transform: rotate(90deg);
  }

  #spec-sidebar-list ul li .submenu-title {
    position: relative;
    display: block;
    font-size: 15px;
    font-weight: 500;
    color: rgba(0,0,0,.85);
    cursor: pointer;
  }

  #spec-sidebar-list ul li .submenu-title:after {
    position: absolute;
    display: block;
    content: '';
    top: 2px;
    left: -1rem;
    width: 0; 
    height: 0; 
    border-top: 5px solid transparent;
    border-bottom: 5px solid transparent;
    border-left: 5px solid black;
  }

  #spec-sidebar-list ul li .submenu-items {
    max-height: 0;
    overflow: hidden;
  }

  #spec-sidebar-list ul li .submenu-items a {
    display: block;
    font-size: 14px;
    line-height: 1.2;
    font-weight: normal;
    color: rgba(0,0,0,.7);
  }

  #spec-sidebar-list ul li .submenu-items a:hover {
    color: rgba(0,0,0,1);
  }

  #spec-sidebar-list ul li .submenu-items li.active {
    background: rgba(0,0,0,.05);
  }

  #spec-sidebar-list ul li .submenu-items li.active a {
    font-weight: 500;
  }

  #spec-sidebar-list ul li .method:before {
    display: none;
    width: 47px;
    margin-right: .5rem;
    padding-top: .15rem;
    color: #fff;
    text-align: center;
    font-weight: normal;
    font-size: 11px;
    line-height: 1rem;
    border-radius: 2px;
    vertical-align: bottom;
  }

  #spec-sidebar-list ul li .method-post:before {
    content: "POST";
    background: #248FB2;
  }

  #spec-sidebar-list ul li .method-put:before {
    content: "PUT";
    background: #9B6F8A;
  }

  #spec-sidebar-list ul li .method-get:before {
    content: "GET";
    background: #6ABD5A;
  }

  #spec-sidebar-list ul li .method-delete:before {
    content: "DELETE";
    background: #E2797A;
  }
</style>
]],
    auth = true
  },
  {
    type = "page",
    name = "guides/5-minute-quickstart",
    contents = [[{{#> layout pageTitle="Dev Portal - 5 Minute Quickstart" }}

  {{#* inline "content-block"}}
    <div class="app-container">
      <div class="container">
        {{> guides/sidebar}}
        <section class="page-wrapper kong-doc">
          <h1>5-minute Quickstart</h1>
          <p>In this section, you’ll learn how to manage your Kong Enterprise Edition (EE)
          instance. First we’ll
          have you start Kong to give you access to the RESTful Admin API, and easy-to-use
          Admin GUI, through which you manage your APIs, consumers, and more. Data sent
          through the Admin API and GUI is stored in Kong’s <a href="https://getkong.org/docs/latest/configuration/#datastore-section">datastore</a>
          (Kong supports PostgreSQL and Cassandra).</p>

          <h3>1. Start Kong EE</h3>
          <p>Issue the following command to prepare your datastore by running the Kong
          migrations:</p>

          <pre><code class="language-bash">$ kong migrations up [-c /path/to/kong.conf]</code></pre>

          <p>You should see a message that tells you Kong has successfully migrated your
          database. If not, you probably incorrectly configured your database
          connection settings in your configuration file.</p>
          <p>Now let’s <a href="https://getkong.org/docs/latest/cli">start</a> Kong:</p>

          <pre><code class="language-bash">$ kong start [-c /path/to/kong.conf]</code></pre>

          <p><strong>Note:</strong> the CLI accepts a configuration option (<code>-c /path/to/kong.conf</code>)
          allowing you to point to your own configuration.</p>

          <h3>2. Verify that Kong EE has started successfully</h3>
          <p>If everything went well, you should see a message (<code>Kong started</code>)
          informing you that Kong is running.</p>
          <p>By default Kong listens on the following ports:</p>

          <ul>
            <li><code>:8000</code> on which Kong listens for incoming HTTP traffic from your
            clients, and forwards it to your upstream services.</li>
            <li><code>:8443</code> on which Kong listens for incoming HTTPS traffic. This port has a
            similar behavior as the <code>:8000</code> port, except that it expects HTTPS
            traffic only. This port can be disabled via the configuration file.</li>
            <li><code>:8001</code> on which the <a href="https://getkong.org/docs/latest/admin-api">Admin API</a> used to configure Kong listens.</li>
            <li><code>:8444</code> on which the <a href="https://getkong.org/docs/latest/admin-api">Admin API</a> listens for HTTPS traffic.</li>
          </ul>

          <h3>3. Stop Kong EE</h3>
          <p>As needed you can stop the Kong process by issuing the following <a href="https://getkong.org/docs/latest/cli">command</a>:</p>

          <pre><code class="language-bash">$ kong stop</code></pre>

          <h3>4. Reload Kong EE</h3>
          <p>Issue the following command to <a href="https://getkong.org/docs/latest/cli">reload</a> Kong without downtime:</p>

          <pre><code class="language-bash">$ kong reload</code></pre>

          <h2>Next Steps</h2>
          <p>Now that you have Kong EE running you can interact with the Admin API.</p>
          <p>To begin, go to <a href="{{config.PORTAL_GUI_URL}}/docs/enterprise/latest/getting-started/adding-your-api">Adding your API ›</a></p>
        </section>
      </div>
    </div>
  {{/inline}}

{{/layout}}
]],
    auth = true
  },
  {
    type = "partial",
    name = "unauthenticated/login-actions",
    contents = [[{{#if auth}}
<nav class="header-login-container">
  {{#if isAuthenticated}}
  <li class="dropdownWrapper">
    <div class="header-text">
      {{#if authData.idToken.1.picture}}
        <img class="avatar" src="{{authData.idToken.1.picture}}" />
      {{else}}
        <svg id="default-user-icon" width="32" height="32" xmlns:xlink="http://www.w3.org/1999/xlink">
          <defs>
            <circle id="a" cx="16" cy="16" r="16"/>
          </defs>
          <g fill="none" fill-rule="evenodd">
            <g>
              <use fill-opacity=".75" fill="#FFF" xlink:href="#a"/>
              <circle stroke-opacity=".1" stroke="#000" cx="16" cy="16" r="15.5"/>
            </g>
            <path d="M16 32c-4.7787701 0-9.06822218-2.0950195-12-5.4167024V25c0-2.21 1.79-4 4.046-4 1.824 2.416 4.692 4 7.954 4 3.262 0 6.13-1.584 8-4 2.21 0 4 1.79 4 4v1.5832976C25.0682222 29.9049805 20.7787701 32 16 32zm0-27c3.3137085 0 6 2.6862915 6 6v4c0 3.3137085-2.6862915 6-6 6s-6-2.6862915-6-6v-4c0-3.3137085 2.6862915-6 6-6z" fill-opacity=".35" fill="#0A2233"/>
          </g>
        </svg>
      {{/if}}
      <svg class="dropdown-arrow" width="10px" height="6px" viewBox="0 0 10 6" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
      <g id="Page-1" stroke="none" stroke-width="1" fill="none" fill-rule="evenodd">
        <g id="nav-behavior--desktop" transform="translate(-1170.000000, -36.000000)" fill="#CFD4D9" fill-rule="nonzero">
            <g id="header">
                <g id="nav" transform="translate(1067.000000, 24.000000)">
                    <g id="dd--api-reference" transform="translate(0.000000, 6.000000)">
                        <path d="M107.292893,11.7071068 C107.683418,12.0976311 108.316582,12.0976311 108.707107,11.7071068 L112.707107,7.70710678 C113.097631,7.31658249 113.097631,6.68341751 112.707107,6.29289322 C112.316582,5.90236893 111.683418,5.90236893 111.292893,6.29289322 L108,9.65625 L104.707107,6.29289322 C104.316582,5.90236893 103.683418,5.90236893 103.292893,6.29289322 C102.902369,6.68341751 102.902369,7.31658249 103.292893,7.70710678 L107.292893,11.7071068 Z" id="icn-chevron"></path>
                    </g>
                </g>
            </g>
          </g>
        </g>
      </svg>
    </div>
    <ul class="dropdown-list">
      <li>
        <a href="{{config.PORTAL_GUI_URL}}/dashboard">Dashboard</a>
      </li>
      <li>
        <a href="{{config.PORTAL_GUI_URL}}/settings">Settings</a>
      </li>
      <li>
        <a href="{{config.PORTAL_GUI_URL}}/" id="logout">Logout</a>
      </li>
    </ul>
  </li>
  {{/if}}
  {{#unless isAuthenticated}}
  <li>
    <a href="{{config.PORTAL_GUI_URL}}/login">Login</a>
  </li>
  <li>
    <a href="{{config.PORTAL_GUI_URL}}/register" class="button button-transparent">Sign Up</a>
  </li>
  {{/unless}}
</nav>
{{/if}}
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/custom-css",
    contents = [[{{!--
|--------------------------------------------------------------------------
| Here's where the magic happens. This is where you can add your own
| custom CSS as well as override any default styling we've provided.
| This file is broken up by section, but feel free to organize as you
| see fit!
|
| Helpful articles on customizing your Developer Portal:
|   - https://getkong.org/docs/enterprise/latest/developer-portal/introduction/
|   - https://getkong.org/docs/enterprise/latest/developer-portal/getting-started/
|   - https://getkong.org/docs/enterprise/latest/developer-portal/understand/
|   - https://getkong.org/docs/enterprise/latest/developer-portal/customization/
|   - https://getkong.org/docs/enterprise/latest/developer-portal/authentication/
|   - https://getkong.org/docs/enterprise/latest/developer-portal/faq/
|
|--------------------------------------------------------------------------
|
--}}

{{!-- Custom fonts --}}
{{!-- <link href="https://fonts.googleapis.com/css?family=Roboto" rel="stylesheet">
<link href="//cdnjs.cloudflare.com/ajax/libs/highlight.js/9.12.0/styles/default.min.css" rel="stylesheet"> --}}

<style>
/*
|--------------------------------------------------------------------------
| Typography:
| h1, h2, h3, h4, h5, h6, p
|--------------------------------------------------------------------------
|
*/

h1 {}

h2 {}

h3 {}

h4 {}

h5 {}

h6 {}

p {}

/* Header */
#header {}

/* Sidebar */
#sidebar {}

/* Footer */
#footer {}

/* Swagger UI */
.swagger-ui .side-panel {}

/*
|--------------------------------------------------------------------------
| Code block prismjs theme.
| e.g. https://github.com/PrismJS/prism-themes
|--------------------------------------------------------------------------
|
*/

.token.block-comment,
.token.cdata,
.token.comment,
.token.doctype,
.token.prolog {
  color: #999
}

.token.punctuation {
  color: #ccc
}

.token.attr-name,
.token.deleted,
.token.namespace,
.token.tag {
  color: #e2777a
}

.token.function-name {
  color: #6196cc
}

.token.boolean,
.token.function,
.token.number {
  color: #f08d49
}

.token.class-name,
.token.constant,
.token.property,
.token.symbol {
  color: #f8c555
}

.token.atrule,
.token.builtin,
.token.important,
.token.keyword,
.token.selector {
  color: #cc99cd
}

.token.attr-value,
.token.char,
.token.regex,
.token.string,
.token.variable {
  color: #7ec699
}

.token.entity,
.token.operator,
.token.url {
  color: #67cdcc
}

.token.bold,
.token.important {
  font-weight: 700
}

.token.italic {
  font-style: italic
}

.token.entity {
  cursor: help
}

.token.inserted {
  color: green
}

</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/app-css",
    contents = [[{{!-- application styles --}}
{{> unauthenticated/assets/base/alerts-css }}
{{> unauthenticated/assets/base/base-css }}
{{> unauthenticated/assets/base/fonts-css }}
{{> unauthenticated/assets/base/forms-css }}

{{> unauthenticated/assets/layout/footer-css }}
{{> unauthenticated/assets/layout/sidebar-css }}
{{> unauthenticated/assets/layout/header-css }}
{{> unauthenticated/assets/layout/header-dropdown-css }}

{{> unauthenticated/assets/pages/404-css }}
{{> unauthenticated/assets/pages/guides-css }}
{{> unauthenticated/assets/pages/index-css }}
{{> unauthenticated/assets/pages/login-css }}
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/title",
    contents = [[{{#if pageTitle}}
<script type="text/javascript">
  window.document.title = "{{pageTitle}}"
</script>
{{/if}}
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/icons/loading",
    contents = [[<svg width="18px"  height="18px"  xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" preserveAspectRatio="xMidYMid" class="lds-rolling" style="background: none;"><circle cx="50" cy="50" fill="none" ng-attr-stroke="{{config.color}}" ng-attr-stroke-width="{{config.width}}" ng-attr-r="{{config.radius}}" ng-attr-stroke-dasharray="{{config.dasharray}}" stroke="rgba(30.19607843137255%,30.19607843137255%,30.19607843137255%,0.605)" stroke-width="12" r="30" stroke-dasharray="141.37166941154067 49.12388980384689" transform="rotate(23.8694 50 50)"><animateTransform attributeName="transform" type="rotate" calcMode="linear" values="0 50 50;360 50 50" keyTimes="0;1" dur="1s" begin="0s" repeatCount="indefinite"></animateTransform></circle></svg>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/icons/search-widget",
    contents = [[<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24">
<path d="M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/>
  <path d="M0 0h24v24H0z" fill="none"/>
</svg>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/icons/search-header",
    contents = [[<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24">
  <path d="M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/>
  <path d="M0 0h24v24H0z" fill="none"/>
</svg>
]],
    auth = false
  },
  {
    type = "partial",
    name = "spec/index-vue",
    contents = [[{{!-- imports --}}
{{> search/helpers-js }}

{{!-- template --}}
<div id="spec-index" :class="{ active: !isLoading }">
  <div class="page-header">
    <h1>API Catalog</h1>
    <input name="filter" v-model="filterModel" placeholder="Search"/>
  </div>

  <div v-if="filteredSpecs.length > 0" class="list-items">
    <div v-for="spec in filteredSpecs" class="list-item-container">
      <div @click="goToSpec(spec.filename)" class="list-item">
        <a class="title">${ spec.title }</a>
        <p class="description">${ spec.description }</p>
        <div class="meta">
          <p class="version">version: ${ spec.version }</p>
          <p class="tags">${ formatTags(spec.tags) }</p>
        </div>
      </div>
    </div>
  </div>
  <div v-else class="no-results">
    <h1>No Results</h1>
  </div>
</div>

{{!-- component --}}
<script>
window.registerApp(function () {
  new window.Vue({
    el: '#spec-index',
    delimiters: ['${', '}'],

    data () {
      return {
        specFiles: [],
        filteredSpecs: [],
        filterModel: '',
        isLoading: true,

        buildUrl: () => { console.log('error: buildUrl helper failed to load') },
        goToPage: () => { console.log('error: goToPage helper failed to load') }
      }
    },

    mounted () {
      if (window.helpers) {
        this.buildUrl = window.helpers.buildUrl || this.buildUrl
        this.goToPage = window.helpers.goToPage || this.goToPage
      }

      this.getFiles().then((resp) => {
        this.specFiles = this.fetchSpecs(resp.data.data)
        this.filteredSpecs = this.filterSpecs()
        this.isLoading = false
      })
    },

    methods: {
      getFiles () {
        return window._kong.api.get('/files?type=spec', { withCredentials: true })
      },

      goToSpec(path) {
        let url = this.buildUrl(`documentation/${path}`)
        this.goToPage(url)
      },

      filterSpecs() {
        if (this.filterModel !== '') {
          return this.specFiles.filter((spec) => {
            let specContent = JSON.stringify(spec).toLowerCase()
            let filterParam = this.filterModel.toLowerCase()
            return specContent.includes(filterParam)
          })
        }

        return this.specFiles
      },

      fetchSpecs(files) {
        let specFiles = files.filter((file) => file.type === 'spec')
        return specFiles.map((spec) => {
          let specContents = this.parseSpec(spec.contents)
          let specInfo = specContents.info || {}
          let filename = spec.name
          if (filename.includes('unauthenticated/')) {
            filename = spec.name.split('unauthenticated/')[1]
          }

          return {
            title: specInfo.title || spec.name,
            description: specInfo.description || '',
            version: specInfo.version || 'unknown',
            tags: specContents.tags || [],
            filename: filename || ''
          }
        })
      },

      parseSpec (item) {
        if (!item) return {}

        let parsedItem = this.parseJSON(item)

        if (!parsedItem) {
          parsedItem = this.parseYAML(item)
        }

        if (!parsedItem) {
          parsedItem = {}
        }

        return parsedItem
      },

      parseJSON (item) {
        try {
          return JSON.load(item)
        } catch (e) {
          return false
        }
      },

      parseYAML (item) {
        try {
          return window.YAML.load(item)
        } catch (e) {
          return false
        }
      },

      formatTags (tagObj) {
        if (!tagObj) return ''

        let tags = Object.keys(tagObj).map((tagKey) => { return tagObj[tagKey].name })
        let tagStr = tags.slice(0, 3).join(', ')
        if (tags.length > 3) {
          let extraTags = tags.length - 3
          tagStr += `... (${extraTags} more)`
        }
        return tagStr
      }
    },

    watch: {
      filterModel: {
        handler: function() {
          this.filteredSpecs = this.filterSpecs()
        }
      }
    }
  })
})
</script>

{{!-- style --}}
<style>
#spec-index:not(.active) {
  display: none;
}

#spec-index .list-items {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  margin: 0 132px 48px;
}

#spec-index .no-results {
  text-align: center;
  color: rgba(0,0,0,0.45);
}

#spec-index .page-header {
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  border-bottom: 1px solid #979797;
  margin: 48px 148px;
  padding-bottom: 48px;
}

#spec-index .page-header input {
  background: url(images/search.svg) no-repeat scroll 8px 12px;
  padding-left: 30px;
  font-size: 15px;
  color: rgba(0,0,0,0.45);
}

#spec-index .list-item-container {
  padding: 16px;
   width: 33.3%;
}

@media all and (max-width: 1200px) {
  #spec-index .list-item-container {
    width: 50%;
  }
}

@media all and (max-width: 900px) {
  #spec-index .list-items {
    margin: 0 48px 48px;
  }

  #spec-index .page-header {
    flex-wrap: wrap;
    margin: 48px 64px;
  }

  #spec-index .list-item-container {
    width: 100%;
  }
}

#spec-index .list-item {
  display: flex;
  flex-direction: column;
  border: 1px solid rgba(0,0,0,0.12);
  border-radius: 3px;
  min-height: 190px;
  padding: 24px;
}

#spec-index .list-item:hover {
  cursor: pointer;
}

#spec-index .list-item .title {
  flex-direction: column;
  flex-grow: 0;
  font-size: 18px;
  color: #1270B2;
}

#spec-index .list-item:hover .title {
  text-decoration: underline;
}

#spec-index .list-item .description {
  flex-grow: 1;
  font-size: 16px;
  color: rgba(0,0,0,0.70);
  line-height: 24px;
  max-height: 72px;
  overflow: hidden;
}

#spec-index .list-item .meta {
  display: flex;
  flex-direction: row;
  justify-content: space-between;
  flex-grow: 0;
  font-size: 14px;
  color: rgba(0,0,0,0.45);
  line-height: 20px;
}

.list-item .meta p {
  margin: 0
}

.page-header input {
  height: 40px;
}

.page-header h1 {
  margin: 0;
}
</style>
]],
    auth = true
  },
  {
    type = "partial",
    name = "unauthenticated/assets/layout/footer-css",
    contents = [[<style>
footer#footer {
  z-index: 5;
  justify-content: center;
  height: 68px;
  align-items: center;
  color: rgba(255, 255, 255, 0.65);
  border-top: 1px solid rgba(255, 255, 255, 0.1);
  background-color: #112633;
}
@media all and (max-width: 768px) {
  footer#footer {
    justify-content: center;
    align-items: center;
  }
  footer#footer .container {
    flex-direction: column;
    align-items: center;
  }
}
footer#footer p {
  padding-left: 1rem;
  margin: 0;
  font-weight: 500;
}
@media all and (max-width: 768px) {
  footer#footer p {
    margin-bottom: 1rem;
  }
}
footer#footer .footer-links {
  display: flex;
  margin: 0 0 0 auto;
  list-style: none;
}
footer#footer .footer-links li {
  flex: 1 auto;
  margin: 0 15px;
}
footer#footer .footer-links li a {
  color: rgba(255, 255, 255, 0.65);
  font-weight: 500;
}
footer#footer .footer-links li:hover a {
  color: white;
}
@media all and (max-width: 768px) {
  footer#footer .footer-links {
    padding: 0;
    margin: 0;
  }
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/registration-form-vue",
    contents = [[

{{!-- template --}}
<div id="registration-form">
  <h1>Request Access</h1>
  <div class="alert alert-info">
    <b>Please fill out the below form and we will notify you once your request gets approved.</b>
  </div>
  <form id="register">
    <div class="wrapper" :class="{ loaded: !isLoading }">
      <div v-for="(field, i) in fields" :key="i">
        <label
            :for="field.field_name">${ field.input }</label>
        <input :id="field.field_name"
              :name="field.field_name"
              :type="field.type_of_input"
              :required="field.required" />
      </div>
      <label for="email">Email</label>
      <input v-model="email" id="email" type="text" name="email" required/>
      <div v-if="authType === 'basic-auth'">
          <label for="password">Password</label>
          <input id="password" type="password" name="password" required />
      </div>
      <div v-if="authType === 'key-auth'">
          <label for="key">Api Key</label>
          <input id="key" type="text" name="key" required />
      </div>
    </div>
    <button class="button button-primary" type="submit">Sign Up</button>
  </form>
</div>

{{!-- component --}}
<script style="display: none;">
window.registerApp(function () {
  new window.Vue({
    el: '#registration-form',
    delimiters: ['${', '}'],

    data () {
      return {
        fields: [{}],
        authType: null,
        email: "",
        isLoading: false
      }
    },
    methods: {
      getUrlVars() {
        var vars = {}
        var parts = window.location.href.replace(/[?&]+([^=&]+)=([^&]*)/gi, function(m,key,value) {
          vars[key] = value
        })
        return vars
      },
      getUrlParam (parameter, defaultValue){
        var urlParameter = defaultValue;
        if(window.location.href.indexOf(parameter) > -1){
          urlParameter = this.getUrlVars()[parameter];
        }
        return urlParameter;
      }
    },
    mounted () {
      this.getUrlParam('email', '')
      document.getElementById('register').addEventListener('submit', e => { e.preventDefault() })

      if (window.K_CONFIG) {
        this.authType = window.K_CONFIG.PORTAL_AUTH
        this.fields = window.transformMetaFields(
          window.K_CONFIG.PORTAL_DEVELOPER_META_FIELDS
        )
      }
      this.isLoading = false
    }
  })
})
</script>

<style style="display: none;">
  #registration-form .wrapper:not(.loaded) label {
    color: white;
  }
</style>

]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/assets/pages/index-css",
    contents = [[<style>
#homepage svg {
  max-width: 100%;
}
#homepage section h2 {
  color: #00345a;
  font-size: 32px;
  font-weight: 500;
  margin-bottom: 0.75rem;
  margin-top: 0;
}
#homepage section p.tagline {
  font-size: 1.25rem;
  color: rgba(0, 0, 0, 0.45);
}
#homepage section a:not(.button) {
  color: #1270B2;
}
#homepage section a:not(.button):hover {
  text-decoration: underline;
}
#homepage .hero {
  display: flex;
  min-height: 40vh;
  padding: 6rem 2rem;
  background: #001E33;
  background: linear-gradient(180deg, #001E33 0%, #072d47 100%);
}
#homepage .hero .row {
  align-items: center;
}
#homepage .hero h1 {
  margin: 0;
  font-size: 48px;
  font-weight: 800;
  margin-bottom: 0.75rem;
}
#homepage .hero p {
  font-size: 24;
  font-weight: 400;
  line-height: 1.25;
  margin: 0 0 2rem;
}
#homepage .hero button {
  margin: 10px 0;
}
#homepage .catalog .row:first-child {
  margin-bottom: 3rem;
}
#homepage .catalog .catalog-item {
  display: flex;
  flex: 1;
  flex-direction: column;
  flex-wrap: wrap;
  flex-basis: 100%;
  align-items: center;
  text-align: center;
  margin: 0 1rem;
  padding: 1.5rem;
  border-radius: 0.25rem;
  border: 1px solid rgba(0, 0, 0, 0.1);
}
#homepage .catalog .catalog-item svg {
  margin-bottom: 1rem;
}
#homepage .catalog .catalog-item h3 {
  font-weight: 400;
  font-size: 24;
  color: #00345a;
  margin: 0 0 1rem;
}
#homepage .catalog .catalog-item p {
  margin: 0 0 1rem;
  line-height: 1.5;
  width: 100%;
}
#homepage .catalog .catalog-item p:last-child {
  margin: 0;
}
#homepage .catalog .catalog-item:last-child {
  margin-right: 0;
}
#homepage .catalog .catalog-item:first-child {
  margin-left: 0;
}
#homepage .getting-started {
  background: #F7F7F7;
}
#homepage .getting-started .row:first-child {
  margin-bottom: 3rem;
}
#homepage .getting-started .guide {
  display: flex;
  margin: 0 1rem;
  padding: 1.5rem 0;
  border-top: 1px solid rgba(0, 0, 0, 0.1);
}
#homepage .getting-started .guide .text p {
  margin: 0 0 1rem;
  color: rgba(0, 0, 0, 0.45);
}
#homepage .getting-started .guide .text p.subtitle {
  margin-bottom: 0.75rem;
  font-size: 1.25rem;
  font-weight: 500;
  color: rgba(0, 0, 0, 0.9);
}
#homepage .getting-started .guide:last-child {
  margin-right: 0;
}
#homepage .getting-started .guide:first-child {
  margin-left: 0;
}
#homepage .getting-started .guide .icon {
  padding: 0 1rem;
}
#homepage .footer {
  background-color: #112633;
  justify-content: center;
  background-image: url("data:image/png;base64,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ECBQqYAgdKWFiWYJPtdbGy0jQIDAuQIC0OcKej0BAgQuKCAIfUH8PacWfN6DYhMBAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAgQ6ERCErqfQgs/11EJLCBAgsJSAAPRSso5LgACBFQUEoVfE3nMqwec9KDYRIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECgUwFB6MsVXvD5cvbOTIAAgbUFBKDXFnc+AgQILCggCL0g7p5DCz7vQbGJAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBJ4ICEKvNxAEn9ezdiYCBAjUIiAAXUsltIMAAQIzCghCz4i551CCz3tQbCJAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgACBvQKC0HtZZtko+DwLo4MQIECgSQEB6CbLptEECBA4TkAQ+jinY/cSfD5Wyn4ECBAgQIAAAQIECBAgQIAAAQIECBAgQIAAAQIECBAgUAoIQpcip68LPp9u55UECBDYioAA9FYqqR8ECBAYERCEHsE54inB5yOQ7EKAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECRwkIQh/FtHcnwee9LDYSIECgSwEB6C7LrtMECPQqIAg9rfKCz9O87E2AAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECxwsIQh9vJfh8vJU9CRAg0IuAAHQvldZPAgQI7AgIQu9g7Hko+LwHxSYCBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQWERAEPowq+DzYRvPECBAoHcBAejeR4D+EyDQtYAg9NXyCz5f9bBGgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgAABAusJCEL/aC34/KOFRwQIECCwX0AAer+LrQQIEOhKoPcgtOBzV8NdZwkQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIFC1QM9BaMHnqoemxhEgQKAqAQHoqsqhMQQIELisQG9BaMHny443ZydAgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgACBwwI9BaEFnw+PA88QIECAwH4BAej9LrYSIECga4GtB6EFn7se3jpPgAABAgQIECBAgAABAgQIECBAgAABAgQIECBAgACBpgS2HIQWfG5qKGosAQIEqhIQgK6qHBpDgACBugS2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");
  background-position: center bottom;
  background-size: 100%;
  background-repeat: no-repeat;
  align-items: center;
}
#homepage .footer h2, #homepage .footer p {
  text-align: center;
}
#homepage .footer h2 {
  margin: 0 0 0.75rem;
  font-size: 32px;
  font-weight: 500;
  color: white;
}
#homepage .footer p {
  font-size: 18px;
  font-weight: 400;
  line-height: 30px;
  margin: 0;
}
#homepage .footer button {
  margin-top: 2rem;
}
@media screen and (max-width: 720px) {
  #homepage .row {
    flex-direction: column;
  }
  #homepage .hero {
    padding: 2rem;
  }
  #homepage .hero .column {
    margin-bottom: 1rem;
  }
  #homepage .catalog .catalog-item {
    margin: 1rem 0;
  }
  #homepage .getting-started .guide {
    margin: 1rem 0;
  }
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/footer",
    contents = [[<footer id="footer" class="container column shrink">
  <div class="container">
    <p>&copy; {{ currentYear }} Company, Inc.</p>
    <ul class="footer-links">
      <li>
        <a href="{{config.PORTAL_GUI_URL}}/about">About</a>
      </li>
      <li>
        <a href="{{config.PORTAL_GUI_URL}}/guides">Guides</a>
      </li>
    </ul>
  </div>
</footer>
]],
    auth = false
  },
  {
    type = "partial",
    name = "unauthenticated/layout",
    contents = [[{{#if pageTitle}}
  {{> unauthenticated/title }}
{{/if}}

{{#> styles-block}}
  {{!--
    These are the default styles, but can be overridden.
  --}}
  {{> unauthenticated/assets/app-css }}
  {{> unauthenticated/custom-css}}
{{/styles-block}}

{{#> header-block}}
  {{!--
    The `header` partial is the default content, but can be overridden.
  --}}
  {{> unauthenticated/header }}
{{/header-block}}

{{#> content-block}}
  {{!-- Default content goes here. --}}
{{/content-block}}

{{#> scripts-block}}
  {{!-- Custom scripts can be added. --}}
  {{> unauthenticated/auth-js auth=authData.authType}}
{{/scripts-block}}
]],
    auth = false
  },
  {
    type = "partial",
    name = "search/helpers-js",
    contents = [[{{!-- imports --}}
{{> common-helpers-js }}

<script type="text/javascript">

if (!window.helpers) {
  window.helpers = {}
}

window.helpers.searchFiles = (searchModel, files) => {
  if (searchModel !== '') {
    let searchedFiles = files.filter((file) => {
      let fileContent = JSON.stringify(file).toLowerCase()
      let searchParam = searchModel.toLowerCase()
      return fileContent.includes(searchParam)
    })

    return searchedFiles
  }

  return []
}

window.helpers.searchConfig = {

  /**
   * files to exclude from search, will be filtered based of url path
   * aliases are identified by file title
   * 
   * NOTE: 'unauthenticated/' path will not be included in filter query.
   *       For example, including '404' will filter pages with the both
   *       the path of '404' and 'unauthenticated/404'
   */
  blacklist: [
    '404',
    'user',
    'search',
    'unauthorized',
    'reset-password',
    'documentation/loader',
    'documentation/api1',
    'documentation/api2'
  ],

  /**
   * key/value pairs which describe title aliases for particular results,
   * aliases are identified by file title
   */
  aliasList: {
    'index': 'home',
    'guides/index': 'guides',
    'documentation/index': 'documentation'
  }
}

window.helpers.fetchPageList = (files) => {

  /**
   * Parse file with type 'page' into title, functional path, authType, & alias.
   *   - title: 'unauthenticated/guides/index' => 'index'
   *   - path: 'unauthentciated/guides/index' => 'guides/index'
   *   - auth: file.auth (true/false)
   *   - alias: is applied if alias value exists in search config object
   */
  let getPageResults = function (files) {

    let pages = files.filter(file => { return file.type === 'page' })

    return pages.map(page => {
      let splitTitle = page.name.split('/')
      let title = splitTitle[splitTitle.length - 1]
      let splitPath = page.name.split('unauthenticated/')
      let path = splitPath[splitPath.length - 1]

      let searchConfig = window.helpers.searchConfig
      let aliasList = searchConfig && searchConfig.aliasList
        ? searchConfig.aliasList
        : {}

      return {
        title: title,
        path: path,
        auth: page.auth,
        alias: aliasList[path]
      }
    })
  }

  /**
   * Locate 'loader' files needed to serve spec files & compile virtual routes for search
   *   - title: 'specs/files.yaml' => 'files.yaml' (simply the spec name)
   *   - path: 'documentation/loader' + 'specs/files.yaml' => 'documentation/files' (loader path + spec title)
   *   - auth: file.auth (true/false)
   *   - alias: is applied if alias value exists in search config object
   */
  let getSpecResults = function (files) {

    let virtualPages = []

    let specs = files.filter(file => { return file.type === 'spec' })
    let loaders = files.filter(file => { return file.name.includes('loader') })

    loaders.forEach(loader => {
      specs.forEach(spec => {
        let splitTitle = spec.name.split('/')
        let title = splitTitle[splitTitle.length - 1]
        let splitPath = loader.name.split('unauthenticated/')
        let initPath = splitPath[splitPath.length - 1]
        let virtualPath = initPath.split('loader')[0] + title
        
        let searchConfig = window.helpers.searchConfig
        let aliasList = searchConfig && searchConfig.aliasList
          ? searchConfig.aliasList
          : {}

        virtualPages.push({
          title: title,
          path: virtualPath,
          auth: loader.auth,
          alias: aliasList[virtualPath]
        })

      })
    })

    return virtualPages
  }

  /**
   * Remove unwanted files from search pool. This includes:
   *   - unauthenticated files when an authenticated version exists
   *   - files which path shows up on the blacklist
   */
  let filterFilesList = function (files) {

    return files.filter(file => {
      let searchConfig = window.helpers.searchConfig
      let blacklist = searchConfig && searchConfig.blacklist
        ? searchConfig.blacklist
        : []

      // Return false if on blacklist
      if (blacklist.includes(file.path)) {
        return false
      }

      // Return true if authenticated
      if (file.auth) {
        return true
      }
      
      // Return true/false if authenticated version exists
      !!files.find(comparisonFile => {
        return (file.path === comparisonFile.path) && comparisonFile.auth
      })
    })
  }

  /**
   * Sort files in alphabetical order
   */
  let sortFiles = function (files) {
    return files.sort((fileA, fileB) => { return fileA.title > fileB.title  })
  }

  let pages = getPageResults(files)
  let specs = getSpecResults(files)
  let fullFiles = pages.concat(specs)
  let filteredFiles = filterFilesList(fullFiles)
  let sortedFiles = sortFiles(filteredFiles)

  return sortedFiles
}
</script>
]],
    auth = true
  },
  {
    type = "partial",
    name = "spec/helpers-js",
    contents = [[{{!-- imports --}}
{{> common-helpers-js }}

<script text="text/javascript">

if (!window.helpers) {
  window.helpers = {}
}

window.helpers.buildSidebar = (parsedSpec) => {
  // If specFile contains array of errors return early
  if (window.helpers.isObject(parsedSpec) === false || !parsedSpec.paths) return

  // Build object of sidebar data from the parsedSpec
  const acc = {} // Set up accumulator object
  Object.keys(parsedSpec.paths).forEach(path => {
    const operationPath = parsedSpec.paths[path]

    Object.keys(operationPath).forEach(method => {
      // If the parsedSpec does not have any tags group everything under default
      let tags = operationPath[method].tags ? operationPath[method].tags : ['default']
      tags.forEach(tag => {
        const operationTag = acc[tag] = acc[tag] || {}
        const operationMethod = operationTag[path] = operationTag[path] || {}
        const operationDetails = operationMethod[method] = operationMethod[method] || {}
        operationDetails.id = operationPath[method].operationId || Object.getOwnPropertyNames(operationMethod)[0] + '_' + buildSidebarURL(Object.getOwnPropertyNames(operationTag).slice(-1)[0])
        operationDetails.summary = operationPath[method].summary || operationPath[method].description || 'summary undefined'
      })
    })
  })

  // Transform acc object to an array and sort items to match rendered spec
  const sidebarArray =
    Object
      .keys(acc)
      .map(tag => {
        return {
          tag,
          paths: Object
            .keys(acc[tag])
            .map(path => {
              return {
                path,
                methods: Object
                  .keys(acc[tag][path])
                  .map(method => {
                    return {
                      method,
                      id: acc[tag][path][method].id,
                      summary: acc[tag][path][method].summary
                    }
                  })
              }
            })
        }
      })
      .sort((a, b) => window.helpers.sortAlphabetical(a.tag, b.tag))

  return sidebarArray
}

/*
 * Lookup spec file to render from data attribute on page
 */
window.helpers.retrieveParsedSpec = (name, spec) => {
  if (!spec) {
    throw new Error(`<p>Oops! Looks like we had trouble finding the spec: '${name}'</p>`)
  }

  const contents = spec.contents
  const parsedSpec = parseSpec(contents)

  // If parseSpec returns array of errors then map them to DOM
  if (window.helpers.isObject(parsedSpec) === false) {
    throw new Error(`<p>Oops! Something went wrong while parsing the spec: '${name}'</p>`)
  }
  return parsedSpec
}

window.helpers.addEvent = (parent, evt, selector, handler) => {
  parent.addEventListener(evt, function (event) {
    if (event.target.matches(selector + ', ' + selector + ' *')) {
      handler.apply(event.target.closest(selector), arguments)
    }
  }, false)
}

// Check if spec is json or yaml
function parseSpec (contents) {
  let parsedSpec // Set empty varible to hold spec
  let errorArray = [] // Set empty array to hold any errors

  // Try to parse spec as JSON
  // If parse fails push json error message into errors array
  try {
    parsedSpec = JSON.parse(contents)
  } catch (jsonError) {
    errorArray.push('Error trying to parse JSON:<br>' + jsonError)

    // Try to parse spec as YAML
    // If parse fails push yaml error message into errors array
    try {
      parsedSpec = YAML.load(contents)
    } catch (yamlError) {
      errorArray.push('Error trying to parse YAML:<br>' + yamlError)
    }
  }
  // If parsed is undefined return errors, else return the parsed spec file
  return parsedSpec
}

// Takes string (id) and replaces all instances of / , {} and -
// Characters to properly build URL for sidebar
function buildSidebarURL (string) {
  return string
    .replace(/\//, '')
    .replace(/({|})/g, '_')
    .replace(/\//g, '_')
    .replace(/-/, '_')
}

</script>
]],
    auth = true
  },
  {
    type = "partial",
    name = "unauthenticated/assets/base/forms-css",
    contents = [[<style>
input {
  padding: 9px 13px;
  border-radius: 3px;
  border: solid 1px #E5E5E5;
}

form label {
  padding-bottom: 8px;
}
form input {
  margin-bottom: 16px;
  width: 100%;
}
</style>
]],
    auth = false
  },
  {
    type = "partial",
    name = "guides/sidebar",
    contents = [[<div id="sidebar">
  <div class="sidebar-menu">
    <div class="sidebar-list">
      <ul>
        <li class="list-title">Getting Started</li>
        <li><a href="{{config.PORTAL_GUI_URL}}/guides/kong-ee-introduction">Introduction</a></li>
        <li><a href="{{config.PORTAL_GUI_URL}}/guides/5-minute-quickstart">5 Minute guide to Kong EE</a></li>
      </ul>
    </div>
     <div class="sidebar-list">
      <ul>
      <ul>
        <li class="list-title">Customization</li>
        <li><a href="{{config.PORTAL_GUI_URL}}/guides/uploading-spec">Uploading Spec File</a></li>
      </ul>
      <ul>
    </div>
     <div class="sidebar-list">
      <ul>
        <li class="list-title">Guides</li>
        <li><a href="{{config.PORTAL_GUI_URL}}/guides/kong-architecture-overview">Kong Architecture</a></li>
        <li><a href="{{config.PORTAL_GUI_URL}}/guides/kong-vitals">Intro to Kong Vitals</a></li>
      </ul>
    </div>
  </div>
</div>
]],
    auth = true
  }
}
