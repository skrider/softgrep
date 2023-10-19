# softgrep

Code semantic search tool. Uses tree-sitter to quickly parse files in a language-aware manner, and generates embeddings on a remote server over gRPC. Uses embeddings to perform semantic search. Takes full advantage of parallelism to parse files and tokenize semantic chunks. Fully language agnostic with tree-sitter. Aware of git. Caches results for increased performance. Like ripgrep except for semantic search.

At a high level, the flow looks like:

cli -> walk directory -> chunk version controlled files with tree sitter -> tokenize via huggingface fast tokenizer -> generate embeddings remotely via gRPC client -> cosine distance nearest neighbor search on flat index

The embedding service runs remotely on Triton. Right now am using microsoft/codebert-base.

