import asyncio
import time
import signal
import logging
import argparse

import numpy as np
import grpc
from grpc_health.v1 import health
from grpc_health.v1 import health_pb2
from grpc_health.v1 import health_pb2_grpc

from pb import softgrep_pb2
from pb import softgrep_pb2_grpc

import ray
from ray.runtime_env import RuntimeEnv

import rpdb

logging.basicConfig(level=logging.INFO)

# address is populated by kubernetes via RAY_ADDRESS
logging.info("initializing ray")

rpdb.set_trace()

runtime_env = RuntimeEnv(
    conda="""
name: env-name
channels:
  - nvidia
  - pytorch
  - conda-forge
  - defaults
dependencies:
  - python=3.7
  - codecov
  - pytorch
  - torchvision
  - torchaudio
  - pytorch-cuda=11.8
  - numpy
"""
)

ray.init(runtime_env=runtime_env)

logging.info(f"ray initialized with {ray.cluster_resources()}")

def parse_arguments():
    logging.info("Parsing arguments")
    parser = argparse.ArgumentParser(description="Parse host and port")
    parser.add_argument("--host", type=str, default="localhost", help="Host to connect")
    parser.add_argument("--port", type=int, default=50051, help="Port to connect")

    args = parser.parse_args()
    return args.host, args.port

@ray.remote(num_gpus=1)
def foo():
    return __import__("torch").cuda.is_available()

class ModelServicer(softgrep_pb2_grpc.Model):
    async def Predict(
        self,
        request: softgrep_pb2.Chunk,
        context: grpc.aio.ServicerContext,
    ) -> softgrep_pb2.Embedding:
        handle = foo.remote()
        vec = ray.get(handle)
        rpdb.set_trace()
        return softgrep_pb2.Embedding(vec=vec)


class LoggingInterceptor(grpc.aio.ServerInterceptor):
    async def intercept_service(self, continuation, handler_call_details):
        method = handler_call_details.method
        logging.info(f"{time.asctime(time.localtime())} Received request: {method}")
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

    await server.start()
    health_servicer.set("liveness", health_pb2.HealthCheckResponse.SERVING)
    health_servicer.set("readiness", health_pb2.HealthCheckResponse.SERVING)
    logging.info("Waiting for termination")
    await server.wait_for_termination()

if __name__ == "__main__":
    loop = asyncio.get_event_loop()
    logging.basicConfig(level=logging.INFO)
    loop.add_signal_handler(signal.SIGINT, exit)
    loop.run_until_complete(serve())

