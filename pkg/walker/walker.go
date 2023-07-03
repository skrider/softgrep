package walker

import (
	"fmt"
	"os"
	"regexp"

	ignore "github.com/denormal/go-gitignore"
	"github.com/karrick/godirwalk"
)

type EmitterFunc func(osPathname string, file *os.File) error

type Walker struct {
	ignoreFiles []*ignore.GitIgnore
	skipRe      *regexp.Regexp
	seenPaths   map[string]bool
	walkOptions *godirwalk.Options
	emitter     EmitterFunc
}

var SKIP_RE *regexp.Regexp

func init() {
	SKIP_RE, _ = regexp.Compile("(/.git|/node_modules|[^/].log|\\w.lock|.zip|.tgz)$")
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

func (w *Walker) callback(osPathname string, directoryEntry *godirwalk.Dirent) error {
	if _, ok := w.seenPaths[osPathname]; ok {
		return godirwalk.SkipThis
	}
	w.seenPaths[osPathname] = true

	if w.skipRe.MatchString(osPathname) {
		return godirwalk.SkipThis
	}
	for _, ignoreFile := range w.ignoreFiles {
		if (*ignoreFile).Ignore(osPathname) {
			return godirwalk.SkipThis
		}
	}

	if directoryEntry.IsDir() {
		// ensure we parse .gitignore before entering directory
		ignorePath := fmt.Sprintf("%s/.gitignore", osPathname)
		if _, err := os.Stat(ignorePath); err == nil {
			if ignoreFile, err := ignore.NewFromFile(ignorePath); err == nil {
				w.ignoreFiles = append(w.ignoreFiles, &ignoreFile)
			}
		}
	}

	if directoryEntry.IsRegular() {
		file, err := os.Open(osPathname)
		if err != nil {
			return err
		}
		if !IsBinary(file) {
			return w.emitter(osPathname, file)
		}
	}
	return nil
}

func NewWalker(emitter EmitterFunc) *Walker {
	return &Walker{
		ignoreFiles: make([]*ignore.GitIgnore, 0),
		skipRe:      SKIP_RE,
		seenPaths:   make(map[string]bool),
		emitter:     emitter,
	}
}

func (w *Walker) Walk(path string) error {
	return godirwalk.Walk(path, &godirwalk.Options{
		Callback:            w.callback,
		FollowSymbolicLinks: true,
	})
}
