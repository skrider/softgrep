# softgrep

Code semantic search tool. Uses tree-sitter to quickly parse files in a language-aware manner, and generates embeddings on a remote server over gRPC. Uses embeddings to perform semantic search. Caches results for increased performance. Like ripgrep except for semantic search.

At a high level, the flow looks like:

cli -> walk directory -> tokenize version controlled files with tree sitter -> generate embeddings remotely -> cosine distance nearest neighbor search

The embedding generation service involves a Kubernetes cluster with a python service consuming requests and leveraging a Ray cluster to generate embeddings statelessly, allowing the GPU usage to scale to zero if necessary.

