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
