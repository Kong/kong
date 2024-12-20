all: target/targetservice_grpc.pb.go

target/targetservice.pb.go: targetservice.proto
	protoc -I . $^ --go_out=target/ --go_opt=paths=source_relative

target/targetservice_grpc.pb.go: targetservice.proto
	protoc -I . $^ --go_out=target/ --go-grpc_out=target/ --go_opt=paths=source_relative
