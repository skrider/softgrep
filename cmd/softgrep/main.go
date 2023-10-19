package main

import (
	"flag"
	"io"
	"log"
	"os"
	"runtime"
	"sync"

	"github.com/skrider/softgrep/pkg/chunk"
	"github.com/skrider/softgrep/pkg/config"
	"github.com/skrider/softgrep/pkg/tokenize"
	"github.com/skrider/softgrep/pkg/walker"
)

const USAGE string = `softgrep 0.0.1
Stephen Krider <skrider@berkeley.edu>

Softgrep recursively searches the current directory for a semantic query.
By default, softgrep will respect gitignore rules and automatically skip
hidden files and directories and binary files.

Softgrep requires an HTTP/2 connection to a remote server to generate
embeddings.

Softgrep by deault will parse a file using language-specific parsers and
generate embeddings for each chunk.

If deployed in a git repo(s), Softgrep will only look at the current state 
of files in HEAD.

USAGE: 
    softgrep [OPTIONS] QUERY [PATH...]
    softgrep [OPTIONS] QUERY
    command | softgrep [OPTIONS] QUERY

ARGS:
    <QUERY>
        A textual search query to dual-embed against the contents of the
        files
    <PATH...>
        Files or directories to search. Directories are searched recursively.

OPTIONS:
    --stride: Number of tokens to use per chunk
`

func printUsage() {
	log.Fatal(USAGE)
}

type ChunkSource struct {
	Reader io.Reader // reader to read from
	Type   string    // type to determine tree sitter parser. If empty, no type is used.
	Name   string    // filename or - for STDIN
}

type Chunk struct {
	Content string
}

func IsBinary(file *os.File) bool {
	bytes := make([]byte, 1024)
	n, _ := file.Read(bytes)
	for _, b := range bytes[:n] {
		if b == 0 {
			return true
		}
	}
	file.Seek(0, 0)
	return false
}

var NUM_WORKERS = runtime.NumCPU() - 1

// TODO one goroutine per embed req

func main() {
	config := config.NewConfig()

	flag.Usage = printUsage
	flag.Parse()

	args := flag.Args()
	var entryPaths []string
	if len(args) == 0 {
		cwd, err := os.Getwd()
		if err != nil {
			log.Panicf("Error: Error getting working directory: %s", err)
		}
		entryPaths = []string{cwd}
	} else {
		entryPaths = args
	}

	parseCh := make(chan ChunkSource, NUM_WORKERS)
	var wg sync.WaitGroup

	chunkCh := make(chan string)
	for i := 0; i < NUM_WORKERS; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			var entry ChunkSource
			defer func() {
				if r := recover(); r != nil {
					log.Fatalf("Recovered in worker %d: %s: %s", i, entry.Name, r)
				}
			}()
			for entry = range parseCh {
				chunker, err := chunk.NewChunker(entry.Name, entry.Reader, &config)
				if err != nil {
                    if err == chunk.BinaryFileError {
                        log.Printf("Worker %d: skipping suspected binary file %s", i, entry.Name)
                    } else {
                        log.Printf("Worker %d: error parsing %s: %s", i, entry.Name, err)
                    }
					continue
				}

				for token, err := chunker.Next(); err == nil; token, err = chunker.Next() {
					chunkCh <- token
				}
				if err != io.EOF {
					log.Printf("Error: Error parsing %s: %s", entry.Name, err)
				}

				if closer, ok := entry.Reader.(io.Closer); ok {
					entry.Reader = nil
					closer.Close()
				}
			}
		}(i)
	}

    tokenCh := make(chan *tokenize.TokenizedChunk, 512)
    for i := 0; i < NUM_WORKERS; i++ {
        wg.Add(1)
        go func(i int) {
            defer wg.Done()
            for chunk := range chunkCh {
                t := tokenize.NewTokenizer(chunk)
                for token := t.Next(); token != nil; token = t.Next() {
                    tokenCh <- token
                }
            }
        }(i)
    }

	emitter := func(osPathname string, file *os.File) error {
        println(osPathname)
		parseCh <- ChunkSource{
			Name:   osPathname,
			Reader: file,
		}
		return nil
	}
	w := walker.NewWalker(emitter)


    go func () {
        for t := range tokenCh {
            log.Println(t.String())
        }
    }()

	useStdin := false
	for _, path := range entryPaths {
		if path == "-" && !useStdin {
			stdinInfo, _ := os.Stdin.Stat()
			if (stdinInfo.Mode() & os.ModeCharDevice) == 0 {
				parseCh <- ChunkSource{
					Reader: os.Stdin,
					Name:   "-",
				}
				useStdin = true
			} else {
				log.Panic("Error: Pipe not found")
			}
		} else {
			err := w.Walk(path)
			if err != nil {
				log.Panic(err)
			}
		}
	}

    wg.Wait()
}
