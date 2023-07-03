package embed

import (
	"fmt"

	"github.com/skrider/softgrep/pb"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func NewClient(host string, port string) (pb.ModelClient, error) {
	var opts []grpc.DialOption
	opts = append(opts, grpc.WithTransportCredentials(insecure.NewCredentials()))

	conn, err := grpc.Dial(fmt.Sprintf("%s:%s", host, port), opts...)
	if err != nil {
        return nil, err
	}

	return pb.NewModelClient(conn), nil
}

