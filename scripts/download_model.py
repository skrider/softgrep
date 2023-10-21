#!/bin/env python
import argparse
from transformers import RobertaModel, RobertaTokenizerFast, RobertaConfig
import torch
import torch.nn as nn
import onnx
import onnxruntime
import numpy as np

class RobertaForSearch(nn.Module):
    def __init__(self, encoder):
        super(RobertaForSearch, self).__init__()
        self.encoder = encoder

    def forward(self, input_ids, attention_mask, token_type_ids):
        return self.encoder(input_ids, attention_mask, token_type_ids)[0][:, 0, :]

def main(args):
    device = f"cuda:{args.device_id}"
    
    print("downloading model")
    # get config. We set use_cache to false as we do not need the KV cache to be output as we are
    # only encoding.
    config = RobertaConfig.from_pretrained(args.model)
    config.use_cache = False;
    model = RobertaModel.from_pretrained(args.model, config=config)
    tokenizer = RobertaTokenizerFast.from_pretrained(args.model)
    # config = config_class.from_pretrained(
    
    example_input_raw = " ".join(["Hello world"] * 513)
    example_inputs = tokenizer(example_input_raw)
    input_ids = torch.as_tensor(example_inputs["input_ids"], dtype=torch.int64)[:args.context_width]
    attn_mask = torch.as_tensor(example_inputs["attention_mask"], dtype=torch.int64)[:args.context_width]
    token_type_ids = torch.zeros((args.context_width,), dtype=torch.int64)

    # stack to max batch size
    input_ids = torch.stack([input_ids] * args.max_batch_size).to(device)
    attn_mask = torch.stack([attn_mask] * args.max_batch_size).to(device)
    token_type_ids = torch.stack([token_type_ids] * args.max_batch_size).to(device)

    model.eval()
    model.to(device)

    cls_selector = RobertaForSearch(model)

    print("getting test inputs")
    example_outputs = cls_selector(input_ids, attn_mask, token_type_ids)

    print("exporting model to output.onnx")
    torch.onnx.export(
        cls_selector, 
        (input_ids, attn_mask, token_type_ids),
        "output.onnx",
        input_names=["input_ids", "attention_mask", "token_type_ids"],
        output_names=["embeddings"],
        dynamic_axes={
            "input_ids": [0],
            "attention_mask": [0],
            "token_type_ids": [0],
            "embeddings": [0],
        }
    )

    # test model
    print("verifying correctness")
    onnx_model = onnx.load("output.onnx")
    onnx.checker.check_model(onnx_model)

    # test inference
    ort_session = onnxruntime.InferenceSession("output.onnx")
    ort_inputs = {
        ort_session.get_inputs()[0].name: input_ids.cpu().numpy(), 
        ort_session.get_inputs()[1].name: attn_mask.cpu().numpy(),
        ort_session.get_inputs()[2].name: token_type_ids.cpu().numpy(),
    }
    ort_outs = ort_session.run(None, ort_inputs)
    assert np.allclose(example_outputs[0].cpu().numpy(), ort_outs[0], rtol=1e-03, atol=1e-05)
    __import__('pdb').set_trace()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=str, required=True)
    parser.add_argument("--context-width", type=int, required=True)
    parser.add_argument("--max-batch-size", type=int, required=True)
    parser.add_argument("--device-id", type=int, required=True)
    args = parser.parse_args()

    with torch.no_grad():
        main(args)

