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
