/*
A "hello world" plugin in Go,
which reads a request header and sets a response header.
*/
package main

import (
	"fmt"
	"github.com/Kong/go-pdk"
)

type Config struct {
	Message string
}

func New() interface{} {
	return &Config{}
}

func (conf Config) Access(kong *pdk.PDK) {
	host, err := kong.Request.GetHeader("host")
	if err != nil {
		kong.Log.Err(err.Error())
	}
	message := conf.Message
	if message == "" {
		message = "hello"
	}
	kong.Response.SetHeader("x-hello-from-go", fmt.Sprintf("Go says %s to %s", message, host))
}

func (conf Config) Response(kong *pdk.PDK) {
  srvr, err := kong.ServiceResponse.GetHeader("Server")
  if err != nil {
    kong.Log.Err(err.Error())
  }

  kong.Response.SetHeader("x-hello-from-go-at-response", fmt.Sprintf("got from server '%s'", srvr))
}
