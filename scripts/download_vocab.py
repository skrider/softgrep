#!/bin/env python

from huggingface_hub import HfFileSystem
import argparse
import os

def main(args):
    # create output directory
    output_dir = args.output
    os.makedirs(output_dir, exist_ok=True)

    # download vocab
    fs = HfFileSystem()
    vocab = fs.glob(f"{args.model}/**vocab.json")
    for v in vocab:
        print(f"Downloading {v}")
        fs.download(v, f"{output_dir}/{v}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=str, required=True)
    parser.add_argument("--output", type=str, default="pkg/tokenize")
    args = parser.parse_args()

    main(args)
