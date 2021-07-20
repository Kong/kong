package main

import (
   "github.com/kong/go-pkd"
)
type Config struct{
	ApiKey string
}

func New() interface{}
	return &Config()
}

func (conf Config) Access(Kong *pdk.PDK) {
  key, err := kong.Request.GetQueryArg("key")
  apiKey := conf.ApiKey
  
  if err! = nil {
	kong.Log.Err(err.Error())
}

 x:= make(map[string][]string)
 x["Content-Type"] = append(x["Content-Type"], "application/json")
