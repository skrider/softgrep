import asyncio
import logging
import numpy as np
from concurrent import futures
import threading

import grpc
from grpc_health.v1 import health
from grpc_health.v1 import health_pb2
from grpc_health.v1 import health_pb2_grpc
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

    health_servicer = health.HealthServicer(
        experimental_non_blocking=True,
        experimental_thread_pool=futures.ThreadPoolExecutor(max_workers=10),
    )
    health_pb2_grpc.add_HealthServicer_to_server(health_servicer, server)

    softgrep_pb2_grpc.add_ModelServicer_to_server(ModelEntrypoint(), server)
    listen_addr = "localhost:50051"
    server.add_insecure_port(listen_addr)
    logging.info("Starting server on %s", listen_addr)
    await server.start()
    health_servicer.set("softgrep.Model", health_pb2.HealthCheckResponse.SERVING)
    logging.info("Waiting for termination")
    await server.wait_for_termination()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(serve())

