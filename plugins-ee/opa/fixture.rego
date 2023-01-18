package example

allow1 = true
allow2 = response {
  response := {
    "allow": true,
    "headers": {
      "header-from-opa": "yolo",
    },
  }
}

default allow3 = false
allow3 {
  input.request.http.headers["my-secret-header"] == "open-sesame"
  input.request.http.path == "/request"
}

default allow4 = false
allow4 {
  body:= input.request.http.body
  body == `{"hello":"world"}`
  size:= input.request.http.body_size
  size == 17
}

default allow5 = false
allow5 {
  input.request.http.parsed_body.hello == "earth"
}

default allow_uri_captures = false
allow_uri_captures {
  input.request.http.uri_captures.named.user1 = "111222333"
}

deny1 = false
deny2 = response {
  response := {
    "allow": false,
    "status": 418,
    "headers": {
      "header-from-opa": "yolo-bye",
    },
  }
}

err1 = 42
err2 = response{
  response := {
    "allow": "false",
  }
}

opa_message = response {
  response := {
    "allow": false,
    "status": 418,
    "headers": {
      "header-from-opa": "has-message",
    },
    "message": {
      "error": "Request are rejected",
      "source": "OPA Access Control",
    },
  }
}
