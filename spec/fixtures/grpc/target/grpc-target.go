package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"math"
	"net"

	pbx "target/targetextras"
	pb "target/targetservice"

	"github.com/mennanov/fmutils"
	"google.golang.org/grpc"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/fieldmaskpb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const (
	port = ":15010"
)

type server struct {
	pb.UnimplementedBouncerServer
}

func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloResponse, error) {
	return &pb.HelloResponse{
		Reply:       fmt.Sprintf("hello %s", in.GetGreeting()),
		BooleanTest: in.GetBooleanTest(),
	}, nil
}

func (s *server) BounceGoodTimes(ctx context.Context, in *pb.BounceGoodTimesRequest) (*pb.BounceGoodTimesResponse, error) {
	now := in.GetNow().AsTime()
	when := in.GetWhen().AsTime()
	delay := in.GetPostponement().AsDuration()

	new_when := when.Add(delay)
	new_delay := new_when.Sub(now)

	return &pb.BounceGoodTimesResponse{
		Now:        timestamppb.New(now),
		NewWhen:    timestamppb.New(new_when),
		TotalDelay: durationpb.New(new_delay),
	}, nil
}

func (c *server) BounceScalars(ctx context.Context, in *pb.ScalarTypes) (*pb.ScalarTypes, error) {
	response := &pb.ScalarTypes{
		DoubleVal:   2 * in.GetDoubleVal(),
		FloatVal:    2 * in.GetFloatVal(),
		Int64Val:    2 * in.GetInt64Val(),
		Uint64Val:   2 * in.GetUint64Val(),
		Sint64Val:   2 * in.GetSint64Val(),
		Fixed64Val:  2 * in.GetFixed64Val(),
		Sfixed64Val: 2 * in.GetSfixed64Val(),
		Int32Val:    2 * in.GetInt32Val(),
		Uint32Val:   2 * in.GetUint32Val(),
		Sint32Val:   2 * in.GetSint32Val(),
		Fixed32Val:  2 * in.GetFixed32Val(),
		Sfixed32Val: 2 * in.GetSfixed32Val(),
		BoolVal:     !in.GetBoolVal(),
		BytesVal:    append(in.GetBytesVal(), 32, 97, 98, 99),
		StringVal:   "hello " + in.GetStringVal(),
	}

	for _, v := range in.GetDoubleVals() {
		response.DoubleVals = append(response.DoubleVals, 2*v)
	}
	for _, v := range in.GetFloatVals() {
		response.FloatVals = append(response.FloatVals, 2*v)
	}
	for _, v := range in.GetInt64Vals() {
		response.Int64Vals = append(response.Int64Vals, 2*v)
	}
	for _, v := range in.GetUint64Vals() {
		response.Uint64Vals = append(response.Uint64Vals, 2*v)
	}
	for _, v := range in.GetSint64Vals() {
		response.Sint64Vals = append(response.Sint64Vals, 2*v)
	}
	for _, v := range in.GetFixed64Vals() {
		response.Fixed64Vals = append(response.Fixed64Vals, 2*v)
	}
	for _, v := range in.GetSfixed64Vals() {
		response.Sfixed64Vals = append(response.Sfixed64Vals, 2*v)
	}
	for _, v := range in.GetInt32Vals() {
		response.Int32Vals = append(response.Int32Vals, 2*v)
	}
	for _, v := range in.GetUint32Vals() {
		response.Uint32Vals = append(response.Uint32Vals, 2*v)
	}
	for _, v := range in.GetSint32Vals() {
		response.Sint32Vals = append(response.Sint32Vals, 2*v)
	}
	for _, v := range in.GetFixed32Vals() {
		response.Fixed32Vals = append(response.Fixed32Vals, 2*v)
	}
	for _, v := range in.GetSfixed32Vals() {
		response.Sfixed32Vals = append(response.Sfixed32Vals, 2*v)
	}
	for _, v := range in.GetBoolVals() {
		response.BoolVals = append(response.BoolVals, !v)
	}
	for _, v := range in.GetBytesVals() {
		response.BytesVals = append(response.BytesVals, append(v, 32, 97, 98, 99))
	}
	for _, v := range in.GetStringVals() {
		response.StringVals = append(response.StringVals, "hello "+v)
	}

	return response, nil
}

func (c *server) BounceWrappers(ctx context.Context, in *pb.WrapperTypes) (*pb.WrapperTypes, error) {
	response := &pb.WrapperTypes{
		DoubleWrapper: wrapperspb.Double(2 * in.GetDoubleWrapper().GetValue()),
		FloatWrapper:  wrapperspb.Float(2 * in.GetFloatWrapper().GetValue()),
		Int64Wrapper:  wrapperspb.Int64(2 * in.GetInt64Wrapper().GetValue()),
		Uint64Wrapper: wrapperspb.UInt64(2 * in.GetUint64Wrapper().GetValue()),
		Int32Wrapper:  wrapperspb.Int32(2 * in.GetInt32Wrapper().GetValue()),
		Uint32Wrapper: wrapperspb.UInt32(2 * in.GetUint32Wrapper().GetValue()),
		BoolWrapper:   wrapperspb.Bool(!in.GetBoolWrapper().GetValue()),
		StringWrapper: wrapperspb.String("hello " + in.GetStringWrapper().GetValue()),
		BytesWrapper:  wrapperspb.Bytes(append(in.GetBytesWrapper().GetValue(), 32, 97, 98, 99)),
	}

	for _, v := range in.DoubleWrappers {
		response.DoubleWrappers = append(response.DoubleWrappers, wrapperspb.Double(2*v.GetValue()))
	}
	for _, v := range in.FloatWrappers {
		response.FloatWrappers = append(response.FloatWrappers, wrapperspb.Float(2*v.GetValue()))
	}
	for _, v := range in.Int64Wrappers {
		response.Int64Wrappers = append(response.Int64Wrappers, wrapperspb.Int64(2*v.GetValue()))
	}
	for _, v := range in.Uint64Wrappers {
		response.Uint64Wrappers = append(response.Uint64Wrappers, wrapperspb.UInt64(2*v.GetValue()))
	}
	for _, v := range in.Int32Wrappers {
		response.Int32Wrappers = append(response.Int32Wrappers, wrapperspb.Int32(2*v.GetValue()))
	}
	for _, v := range in.Uint32Wrappers {
		response.Uint32Wrappers = append(response.Uint32Wrappers, wrapperspb.UInt32(2*v.GetValue()))
	}
	for _, v := range in.BoolWrappers {
		response.BoolWrappers = append(response.BoolWrappers, wrapperspb.Bool(!v.GetValue()))
	}
	for _, v := range in.StringWrappers {
		response.StringWrappers = append(response.StringWrappers, wrapperspb.String("hello "+v.GetValue()))
	}
	for _, v := range in.BytesWrappers {
		response.BytesWrappers = append(response.BytesWrappers, wrapperspb.Bytes(append(v.GetValue(), 32, 97, 98, 99)))
	}

	return response, nil
}

func (c *server) BounceStruct(ctx context.Context, in *structpb.Struct) (*structpb.Struct, error) {
	response, _ := structpb.NewStruct(map[string]interface{}{})

	var HandleValue func(v *structpb.Value) *structpb.Value

	HandleValue = func(v *structpb.Value) *structpb.Value {
		switch x := v.GetKind().(type) {
		case *structpb.Value_NullValue:
			return structpb.NewStringValue("no more null")
		case *structpb.Value_NumberValue:
			switch {
			case math.IsNaN(v.GetNumberValue()):
				return structpb.NewStringValue("not a number")
			case math.IsInf(v.GetNumberValue(), +1):
				return structpb.NewStringValue("infinity")
			case math.IsInf(v.GetNumberValue(), -1):
				return structpb.NewStringValue("-infinity")
			default:
				return structpb.NewNumberValue(2 * v.GetNumberValue())
			}
		case *structpb.Value_StringValue:
			return structpb.NewStringValue("hello " + v.GetStringValue())
		case *structpb.Value_BoolValue:
			return structpb.NewBoolValue(!v.GetBoolValue())
		case *structpb.Value_StructValue:
			struct_val, _ := structpb.NewStruct(map[string]interface{}{})

			for k, v := range x.StructValue.Fields {
				struct_val.Fields[k] = HandleValue(v)
			}

			return structpb.NewStructValue(struct_val)

		case *structpb.Value_ListValue:
			list_val, _ := structpb.NewList([]interface{}{})

			for _, v := range x.ListValue.GetValues() {
				list_val.Values = append(list_val.Values, HandleValue(v))
			}

			return structpb.NewListValue(list_val)
		}
		return structpb.NewStringValue("Undefined")
	}

	for k, v := range in.Fields {
		response.Fields[k] = HandleValue(v)
	}
	return response, nil
}

func (c *server) BounceMaskedFields(ctx context.Context, in *pb.BounceMaskedFieldsRequest) (*pb.BounceMaskedFieldsResponse, error) {
	var HandleComplex func(v *pb.ComplexType) *pb.ComplexType
	var HandleExtras func(v *pbx.ExtraType) *pbx.ExtraType
	var HandleString func(v *wrapperspb.StringValue) *wrapperspb.StringValue
	var HandleAny func(v *anypb.Any) (*anypb.Any, error)

	HandleComplex = func(v *pb.ComplexType) *pb.ComplexType {
		response := &pb.ComplexType{
			Int64Val: v.GetInt64Val() * 2,
			Int32Val: v.GetInt32Val() * 2,
			BoolVal:  !v.GetBoolVal(),
			EnumVal:  v.GetEnumVal(),
		}

		if v.GetBytesVal() != nil {
			response.BytesVal = append(v.GetBytesVal(), 32, 97, 98, 99)
		}

		if v.GetStringVal() != "" {
			response.StringVal = "hello " + v.GetStringVal()
		}

		if v.GetIntMap() != nil {
			response.IntMap = make(map[uint64]*pb.ComplexType)
			for k, v := range v.GetIntMap() {
				response.IntMap[k] = HandleComplex(v)
			}
		}

		if v.GetStringMap() != nil {
			response.StringMap = make(map[string]*pb.ComplexType)
			for k, v := range v.GetStringMap() {
				response.StringMap[k] = HandleComplex(v)
			}
		}

		if v.GetComplexValue() != nil {
			response.ComplexValue = HandleComplex(v.ComplexValue)
		}

		for _, v := range v.GetComplexValues() {
			response.ComplexValues = append(response.ComplexValues, HandleComplex(v))
		}

		if v.GetAny() != nil {
			m, err := HandleAny(v.GetAny())

			if err != nil {
				response.AnyProcessed = false
				response.Any = nil
				fmt.Println(err)
			} else {
				response.AnyProcessed = true
				response.Any = m
			}
		}

		if v.GetFieldMask() != nil {
			var err error
			response.FieldMask, err = fieldmaskpb.New(&pb.ComplexType{}, v.GetFieldMask().GetPaths()...)

			if err != nil {
				fmt.Println(err)
			}

			response.FieldMask.Append(&pb.ComplexType{}, "complex_value.field_mask")
		}

		return response
	}

	HandleExtras = func(v *pbx.ExtraType) *pbx.ExtraType {
		return &pbx.ExtraType{
			Greeting: "hello " + v.GetGreeting(),
		}
	}

	HandleString = func(v *wrapperspb.StringValue) *wrapperspb.StringValue {
		return wrapperspb.String("hello " + v.GetValue())
	}

	HandleAny = func(v *anypb.Any) (*anypb.Any, error) {
		m, err := v.UnmarshalNew()
		if err != nil {
			return nil, err
		}

		switch m := m.(type) {
		case *pb.ComplexType:
			v.UnmarshalTo(m)
			return anypb.New(HandleComplex(m))
		case *pbx.ExtraType:
			v.UnmarshalTo(m)
			return anypb.New(HandleExtras(m))
		case *wrapperspb.StringValue:
			v.UnmarshalTo(m)
			return anypb.New(HandleString(m))
		default:
			return nil, errors.New("Unsupported type for Any: " + v.GetTypeUrl())
		}
	}

	response := HandleComplex(in.GetComplexValue())

	fmutils.Filter(response, in.FieldMask.GetPaths())

	return &pb.BounceMaskedFieldsResponse{
		ComplexValue: response,
	}, nil
}

func (s *server) GrowTail(ctx context.Context, in *pb.Body) (*pb.Body, error) {
	in.Tail.Count += 1

	return in, nil
}

func (s *server) Echo(ctx context.Context, in *pb.EchoMsg) (*pb.EchoMsg, error) {
	return in, nil
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
