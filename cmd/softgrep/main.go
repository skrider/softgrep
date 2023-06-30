package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"os"

	"github.com/karrick/godirwalk"
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

func main() {
    flag.Usage = printUsage
	flag.Parse()
    
    args := flag.Args()
    if len(args) < 1 {
        flag.Usage()
    }

    files := args[1:]
    if len(files) == 0 {
        cwd, _ := os.Getwd()
        files = append(files, cwd)
    }

    entries := make([]*CorpusEntry, 0)

    stdinInfo, _ := os.Stdin.Stat()
    if (stdinInfo.Mode() & os.ModeCharDevice) == 0 {
        entries = append(entries, &CorpusEntry{
            Reader: os.Stdin,
            Name: "-",
        })
    }

    filepaths := make([]string, 0)
    walkFunc := func(osPathname string, directoryEntry *godirwalk.Dirent) error {
        filepaths = append(filepaths, osPathname)
        fmt.Println(osPathname)
        return nil
    }
    
    options := &godirwalk.Options{
        Callback: walkFunc,
    }

    for _, file := range files {
        godirwalk.Walk(file, options)
    }

    fmt.Println(filepaths)
}

