#!/bin/env python

from huggingface_hub import HfFileSystem
import argparse
import os
import tempfile
import json

def main(args):
    # create output directory
    output_dir = args.output
    os.makedirs(output_dir, exist_ok=True)
    
    # create a temp dir
    temp_dir = tempfile.mkdtemp()

    output = {}

    # download vocab
    fs = HfFileSystem()
    # TODO download tokenizer config with the proper schema; this is just the raw vocab
    base = fs.glob(f"{args.base_config}/**tokenizer.json")[0]
    vocab = fs.glob(f"{args.model}/**vocab.json")[0]
    merges = fs.glob(f"{args.model}/**merges.txt")[0]
    for f in [merges, vocab, base]:
        print(f"Downloading {f}")
        fs.download(f, temp_dir)

    base = os.path.basename(base)
    vocab = os.path.basename(vocab)
    merges = os.path.basename(merges)

    # parse base as json, load into output
    with open(os.path.join(temp_dir, base), "r") as f:
        output = json.load(f)

    # load vocab and merges into output
    with open(os.path.join(temp_dir, vocab), "r") as f:
        output["model"]["vocab"] = json.load(f)

    with open(os.path.join(temp_dir, merges), "r") as f:
        output["model"]["merges"] = f.read().split("\n")[:-1]

    # write output to output_dir
    with open(os.path.join(output_dir, "tokenizer.json"), "w") as f:
        json.dump(output, f)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=str, required=True)
    parser.add_argument("--base-config", type=str, default="roberta-base")
    parser.add_argument("--output", type=str, default="pkg/tokenize")
    args = parser.parse_args()

    main(args)
