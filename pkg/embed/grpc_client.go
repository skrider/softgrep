package embed

import (
	"fmt"

	"github.com/skrider/softgrep/pb/triton-client"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func NewClient(host string, port string) (triton_client.GRPCInferenceServiceClient, error) {
	var opts []grpc.DialOption
	opts = append(opts, grpc.WithTransportCredentials(insecure.NewCredentials()))

	conn, err := grpc.Dial(fmt.Sprintf("%s:%s", host, port), opts...)
	if err != nil {
		return nil, err
	}

	return triton_client.NewGRPCInferenceServiceClient(conn), nil
}
