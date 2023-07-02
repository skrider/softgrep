package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"regexp"
	"runtime"
	"sync"

	"github.com/skrider/softgrep/pkg/walker"
	sitter "github.com/smacker/go-tree-sitter"
	"github.com/smacker/go-tree-sitter/golang"
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

type CorpusEntry struct {
    // reader to read from
    Reader io.Reader
    // type to determine tree sitter parser. If empty, no type is used.
    Type string
    // filename or - for STDIN
    Name string
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
// var NUM_WORKERS = 32

const FUNCTION_QUERY = `(function_declaration) @declaration`

// TODO one goroutine per embed req

func main() {
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

    parseCh := make(chan CorpusEntry, NUM_WORKERS)
    var wg sync.WaitGroup
    for i := 0; i < NUM_WORKERS; i++ {
        wg.Add(1)
        go func(i int) {
            defer wg.Done()
            parser := sitter.NewParser()
            lang := golang.GetLanguage()
            parser.SetLanguage(lang)

            re, _ := regexp.Compile("\\.go$")
            for entry := range parseCh {
                fmt.Println(entry.Name)

                if !re.MatchString(entry.Name) {
                    continue
                }

                sourceCode, err := io.ReadAll(entry.Reader)
                if err != nil {
                    log.Panic(err)
                }

                tree := parser.Parse(nil, sourceCode)
                n := tree.RootNode()

                q, _ := sitter.NewQuery([]byte(FUNCTION_QUERY), lang)
                qc := sitter.NewQueryCursor()

                qc.Exec(q, n)

                for {
                    m, ok := qc.NextMatch()
                    if !ok {
                        break
                    }
                    m = qc.FilterPredicates(m, sourceCode)
                    for _, c := range m.Captures {
                        fmt.Println(c.Node.Content(sourceCode))
                    }
                }

                if closer, ok := entry.Reader.(io.Closer); ok {
                    closer.Close()
                }
            }
        }(i)
    }

    emitter := func (osPathname string, file *os.File) error {
        parseCh <- CorpusEntry{
            Name: osPathname,
            Reader: file,
        }
        return nil
    }
    w := walker.NewWalker(emitter)

    useStdin := false
    for _, path := range entryPaths {
        if path == "-" && !useStdin {
            stdinInfo, _ := os.Stdin.Stat()
            if (stdinInfo.Mode() & os.ModeCharDevice) == 0 {
                parseCh <- CorpusEntry{
                    Reader: os.Stdin,
                    Name: "-",
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
    close(parseCh)

    wg.Wait()
}

