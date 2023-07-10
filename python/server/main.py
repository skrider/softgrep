import asyncio
import logging
import numpy as np

import grpc
from pb import softgrep_pb2
from pb import softgrep_pb2_grpc


class ModelEntrypoint(softgrep_pb2_grpc.Model):
    async def Predict(
        self,
        request: softgrep_pb2.Chunk,
        context: grpc.aio.ServicerContext,
    ) -> softgrep_pb2.Embedding:
        print(request.content)
        return softgrep_pb2.Embedding(vec=np.random.randn(100))


async def serve() -> None:
    server = grpc.aio.server()
    softgrep_pb2_grpc.add_ModelServicer_to_server(ModelEntrypoint(), server)
    listen_addr = "[::]:50051"
    server.add_insecure_port(listen_addr)
    logging.info("Starting server on %s", listen_addr)
    await server.start()
    await server.wait_for_termination()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(serve())

