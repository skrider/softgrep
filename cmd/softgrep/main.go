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

	ignore "github.com/denormal/go-gitignore"
	"github.com/karrick/godirwalk"
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

func (c *CorpusEntry) Parse() {

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
            re, _ := regexp.Compile("\\.go$")
            for entry := range parseCh {
                fmt.Println(entry.Name)

                if !re.MatchString(entry.Name) {
                    continue
                }

                parser := sitter.NewParser()

                lang := golang.GetLanguage()
                parser.SetLanguage(lang)

                sourceCode, err := io.ReadAll(entry.Reader)
                if err != nil {
                    log.Panic(err)
                }

                tree := parser.Parse(nil, sourceCode)
                
                n := tree.RootNode()

                query := `(function_declaration
name: (identifier) @function.name
body: (block) @body)`
                q, _ := sitter.NewQuery([]byte(query), lang)
                qc := sitter.NewQueryCursor()

                qc.Exec(q, n)

                for {
                    m, ok := qc.NextMatch()
                    if !ok {
                        break
                    }
                    // Apply predicates filtering
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

    ignoreFiles := make([]ignore.GitIgnore, 0)
    skipRe, _ := regexp.Compile("(/.git|/node_modules|[^/].log|\\w.lock|.zip|.tgz)$")
    seenPaths := make(map[string]bool)

    callback := func(osPathname string, directoryEntry *godirwalk.Dirent) error {
        if _, ok := seenPaths[osPathname]; ok {
            return godirwalk.SkipThis
        }
        seenPaths[osPathname] = true

        if skipRe.MatchString(osPathname) {
            return godirwalk.SkipThis
        }
        for _, ignoreFile := range ignoreFiles {
            if ignoreFile.Ignore(osPathname) {
                return godirwalk.SkipThis
            }
        }

        if directoryEntry.IsDir() {
            // ensure we parse .gitignore before entering directory
            ignorePath := fmt.Sprintf("%s/.gitignore", osPathname)
            if _, err := os.Stat(ignorePath); err == nil {
                if ignoreFile, err := ignore.NewFromFile(ignorePath); err == nil {
                    ignoreFiles = append(ignoreFiles, ignoreFile)
                }
            }
        }

        if directoryEntry.IsRegular() {
            file, err := os.Open(osPathname)
            if err != nil {
                return err
            }
            if !IsBinary(file) {
                parseCh <- CorpusEntry{
                    Reader: file,
                    Name: osPathname,
                }
            }
        }

        return nil
    }
    options := &godirwalk.Options{
        Callback: callback,
        FollowSymbolicLinks: true,
    }

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
            err := godirwalk.Walk(path, options)
            if err != nil {
                log.Panic(err)
            }
        }
    }
    close(parseCh)

    wg.Wait()
}

