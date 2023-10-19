package tokenize

import (
	_ "embed"
	"fmt"
	"sync"

	"github.com/daulet/tokenizers"
)

//go:embed tokenizer.json
var vocab []byte

var tokenizer *tokenizers.Tokenizer

const MAX_LEN = 512

// from https://github.com/microsoft/CodeBERT/blob/master/CodeBERT/codesearch/utils.py:
// The convention in BERT is:
// (a) For sequence pairs:
//  tokens:   [CLS] is this jack ##son ##ville ? [SEP] no it is not . [SEP]
//  type_ids:   0   0  0    0    0     0       0   0   1  1  1  1   1   1
// (b) For single sequences:
//  tokens:   [CLS] the dog is hairy . [SEP]
//  type_ids:   0   0   0   0  0     0   0
//
// Where "type_ids" are used to indicate whether this is the first
// sequence or the second sequence. The embedding vectors for `type=0` and
// `type=1` were learned during pre-training and are added to the wordpiece
// embedding vector (and position vector). This is not *strictly* necessary
// since the [SEP] token unambiguously separates the sequences, but it makes
// it easier for the model to learn the concept of sequences.
//
// For classification tasks, the first vector (corresponding to [CLS]) is
// used as as the "sentence vector". Note that this only makes sense because
// the entire model is fine-tuned.

const CLS_TOKEN = "<s>"
const SEP_TOKEN = "</s>"

var CLS_TOKEN_ID uint32
var SEP_TOKEN_ID uint32
var PAD_TOKEN_ID uint32 = 0

func init() {
	t, err := tokenizers.FromBytes(vocab)
	if err != nil {
		panic(err)
	}
	tokenizer = t

	specialTokensString := fmt.Sprintf("%s %s", CLS_TOKEN, SEP_TOKEN)
	specialTokens, _ := tokenizer.Encode(specialTokensString, false)
	CLS_TOKEN_ID = specialTokens[0]
	SEP_TOKEN_ID = specialTokens[1]
}

type Tokenizer interface {
	Next() *TokenizedChunk
}

type TokenizedChunk struct {
	Tokens    []uint32
	InputIds  []uint32
	InputMask []uint32
	Text      string
}

func newTokenizedChunk() *TokenizedChunk {
	t := &TokenizedChunk{
		Tokens:    make([]uint32, 1, MAX_LEN),
		InputIds:  make([]uint32, 1, MAX_LEN),
		InputMask: make([]uint32, 1, MAX_LEN),
	}
	// add CLS token
	t.Tokens[0] = CLS_TOKEN_ID
	t.InputIds[0] = 0
	t.InputMask[0] = 1
	return t
}

func (t *TokenizedChunk) addToken(token uint32) {
	lenth := len(t.Tokens)
	if lenth == MAX_LEN-1 {
		panic("TokenizedChunk is full")
	}

	t.Tokens = append(t.Tokens, token)
	t.InputIds = append(t.InputIds, 0)
	t.InputMask = append(t.InputMask, 1)
}

func (t *TokenizedChunk) len() int {
	return len(t.Tokens)
}

func (t *TokenizedChunk) finalize() {
	// add SEP token
	t.Tokens = append(t.Tokens, SEP_TOKEN_ID)
	t.InputIds = append(t.InputIds, 0)
	t.InputMask = append(t.InputMask, 1)

	length := len(t.Tokens)
	// pad with zeros
	for i := length; i < MAX_LEN; i++ {
		t.Tokens = append(t.Tokens, PAD_TOKEN_ID)
		t.InputIds = append(t.InputIds, 0)
		t.InputMask = append(t.InputMask, 0)
	}

	t.Text = tokenizer.Decode(t.Tokens, true)
}

func (t *TokenizedChunk) String() string {
	return fmt.Sprintf("Tokens: %v\nInputIds: %v\nInputMask: %v\nText: %s\n", t.Tokens, t.InputIds, t.InputMask, t.Text)
}

type BertTokenizer struct {
	chunks  []*TokenizedChunk
	emitted int
	mu      sync.Mutex
}

func NewTokenizer(text string) Tokenizer {
	// length of a chunk without special tokens
	chunkLen := MAX_LEN - 2
	indices, _ := tokenizer.Encode(text, false)

	// accumulate a token
	chunks := make([]*TokenizedChunk, 0, MAX_LEN)
	chunk := newTokenizedChunk()

	for _, token := range indices {
		if chunk.len() == chunkLen {
			chunk.finalize()
			chunks = append(chunks, chunk)
			chunk = newTokenizedChunk()
		}
		chunk.addToken(token)
	}
	chunk.finalize()
	chunks = append(chunks, chunk)

	return &BertTokenizer{chunks: chunks}
}

func (t *BertTokenizer) Next() *TokenizedChunk {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.emitted >= len(t.chunks) {
		return nil
	}
	chunk := t.chunks[t.emitted]
	t.emitted++
	return chunk
}
