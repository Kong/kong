package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/protobuf/types/known/timestamppb"
	pb "target/targetservice"
)

const (
	port = ":15010"
)

type server struct {
	pb.UnimplementedBouncerServer
}

func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloResponse, error) {
	return &pb.HelloResponse{
		Reply: fmt.Sprintf("hello %s", in.GetGreeting()),
	}, nil
}

func (s *server) BounceIt(ctx context.Context, in *pb.BallIn) (*pb.BallOut, error) {
	w := in.GetWhen().AsTime()
	ago := time.Now().Sub(w)

	reply := fmt.Sprintf("hello %s", in.GetMessage())
	time_message := fmt.Sprintf("%v was %v ago", w, ago)

	return &pb.BallOut{
		Reply:       reply,
		TimeMessage: time_message,
		Now:         timestamppb.New(time.Now()),
	}, nil
}

func main() {
	lis, err := net.Listen("tcp", port)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	s := grpc.NewServer()
	pb.RegisterBouncerServer(s, &server{})
	log.Printf("server listening at %v", lis.Addr())
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
