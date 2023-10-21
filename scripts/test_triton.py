#!/bin/env python
import tritonclient.grpc as grpcclient
import argparse
import numpy as np

def main(args):
    client = grpcclient.InferenceServerClient(f"{args.host}:{args.port}", verbose=True)

    if not client.is_server_live():
        print("Server is not live!")
        exit(1)

    if not client.is_server_ready():
        print("Server is not ready!")
        exit(1)

    model_name = args.model
    model_version = ""
    model_config = client.get_model_config(model_name, model_version)

    # make an inference request
    input_ids = np.random.randint(0, 5000, size=(1, args.context_width), dtype=np.int64)
    attn_mask = np.ones((1, args.context_width), dtype=np.int64)
    token_type_ids = np.zeros((1, args.context_width), dtype=np.int64)

    inputs = []
    outputs = []
    inputs.append(grpcclient.InferInput("input_ids", [1, args.context_width], "INT64"))
    inputs.append(grpcclient.InferInput("attention_mask", [1, args.context_width], "INT64"))
    inputs.append(grpcclient.InferInput("token_type_ids", [1, args.context_width], "INT64"))

    inputs[0].set_data_from_numpy(input_ids)
    inputs[1].set_data_from_numpy(attn_mask)
    inputs[2].set_data_from_numpy(token_type_ids)

    outputs.append(grpcclient.InferRequestedOutput("embeddings"))

    results = client.infer(
        model_name=model_name,
        inputs=inputs,
        outputs=outputs,
    )

    statistics = client.get_inference_statistics(model_name=model_name)
    print(statistics)

    embeddings = results.as_numpy("embeddings")

    print(embeddings.shape)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", type=str, default="localhost")
    parser.add_argument("--port", type=str, default="8001")
    parser.add_argument("--model", type=str, required=True)
    parser.add_argument("--context-width", type=int, default=512)
    parser.add_argument("-n", type=int, required=True)
    args = parser.parse_args()
    main(args)
