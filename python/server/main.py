import asyncio
import signal
import logging
import numpy as np
from concurrent import futures
import argparse

import grpc
from grpc_health.v1 import health
from grpc_health.v1 import health_pb2
from grpc_health.v1 import health_pb2_grpc
from pb import softgrep_pb2
from pb import softgrep_pb2_grpc


def parse_arguments():
    logging.info("Parsing arguments")
    parser = argparse.ArgumentParser(description="Parse host and port")
    parser.add_argument("--host", type=str, default="localhost", help="Host to connect")
    parser.add_argument("--port", type=int, default=50051, help="Port to connect")

    args = parser.parse_args()
    return args.host, args.port


class ModelServicer(softgrep_pb2_grpc.Model):
    async def Predict(
        self,
        request: softgrep_pb2.Chunk,
        context: grpc.aio.ServicerContext,
    ) -> softgrep_pb2.Embedding:
        print(request.content)
        return softgrep_pb2.Embedding(vec=np.random.randn(100))


class LoggingInterceptor(grpc.aio.ServerInterceptor):
    async def intercept_service(self, continuation, handler_call_details):
        method = handler_call_details.method
        logging.info(f"Received request: {method}")
        return await continuation(handler_call_details)

async def serve() -> None:
    server = grpc.aio.server(
            interceptors=(LoggingInterceptor(),)
    )

    health_servicer = health.HealthServicer()
    health_pb2_grpc.add_HealthServicer_to_server(health_servicer, server)

    host, port = parse_arguments()

    softgrep_pb2_grpc.add_ModelServicer_to_server(ModelServicer(), server)
    listen_addr = f"{host}:{port}"
    server.add_insecure_port(listen_addr)
    logging.info("Starting server on %s", listen_addr)

    # Create a new event loop for the server
    loop = asyncio.get_event_loop()

    def stop_server():
        # queue a server halt
        asyncio.get_event_loop().create_task(server.stop(0))

    # Attach the signal handler
    loop.add_signal_handler(signal.SIGINT, stop_server)

    await server.start()
    health_servicer.set("liveness", health_pb2.HealthCheckResponse.SERVING)
    health_servicer.set("readiness", health_pb2.HealthCheckResponse.SERVING)
    logging.info("Waiting for termination")
    await server.wait_for_termination()

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(serve())
