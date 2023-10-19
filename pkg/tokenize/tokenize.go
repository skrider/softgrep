package tokenize

import (
	"io"
	"strings"

	"github.com/skrider/softgrep/pkg/config"
	sitter "github.com/smacker/go-tree-sitter"
)

type Tokenizer interface {
	Next() (string, error)
}

type TSTokenizer struct {
	b    []byte
	qc   *sitter.QueryCursor
	lang *Language
	tree *sitter.Tree
}

func (t *TSTokenizer) Next() (string, error) {
	m, ok := t.qc.NextMatch()
	if !ok {
		return "", io.EOF
	}
	m = t.qc.FilterPredicates(m, t.b)
	var builder strings.Builder
	for _, c := range m.Captures {
		builder.WriteString(c.Node.Content(t.b))
	}
	return builder.String(), nil
}

type StridedTokenizer struct {
	b       []byte
	prevEnd int
	stride  int
	overlap int
}

func (t *StridedTokenizer) Next() (string, error) {
	if t.prevEnd == len(t.b) {
		return "", io.EOF
	}

	start := t.prevEnd - t.overlap
	if start < 0 {
		start = 0
	}
	end := start + t.stride
	if end > len(t.b) {
		end = len(t.b)
	}
	t.prevEnd = end

	return string(t.b[start:end]), nil
}

var BinaryFileError error

func NewTokenizer(filename string, reader io.Reader, config *config.Config) (Tokenizer, error) {
	var lang *Language
	for _, l := range Languages {
		if l.FilePattern.MatchString(filename) {
			lang = l
		}
	}

	b, err := io.ReadAll(reader)
	if err != nil {
		return nil, err
	}

    // check to see if file is binary
    bytesToCheck := 1024
    if len(b) < bytesToCheck {
        bytesToCheck = len(b)
    }
    for i := 0; i < bytesToCheck; i++ {
        if b[i] == 0 {
            return nil, BinaryFileError
        }
    }

	if lang == nil || lang.Strided {
		return &StridedTokenizer{
			b:       b,
			prevEnd: 0,
			stride:  config.Stride,
			overlap: config.Overlap,
		}, nil
	}

	parser := sitter.NewParser()
	l := lang.GetLanguage()
	parser.SetLanguage(l)
	tree := parser.Parse(nil, b)
	n := tree.RootNode()
	q, err := sitter.NewQuery([]byte(lang.Queries[0].Query), l)
	if err != nil {
		return nil, err
	}
	qc := sitter.NewQueryCursor()
	qc.Exec(q, n)

	return &TSTokenizer{
		b:    b,
		tree: tree,
		lang: lang,
		qc:   qc,
	}, nil
}
