---
title: Softgrep
...

# softgrep

Code semantic search tool. Streams files to a backend, detects the language, and then parses with the appropriate parser. Support for embedded languages.

At a high level, the flow looks like:

cli -> stream files -> detect language -> tokenize with tree sitter -> generate embeddings -> push to vector database -> stream nearby responses

Embedding service will be run with python and be highly scalable

