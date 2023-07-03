package util

import (
	"fmt"
	"strings"

	sitter "github.com/smacker/go-tree-sitter"
)

func Pprint(node *sitter.Node) string {
	var writer strings.Builder

	cursor := sitter.NewTreeCursor(node)

	needsNewline := false
	indentLevel := 0
	didVisitChildren := false

	for {
		node := cursor.CurrentNode()
		isNamed := node.IsNamed()
		if didVisitChildren {
			if isNamed {
				_, err := writer.WriteString(")")
				if err != nil {
					// handle error
				}
				needsNewline = true
			}
			if cursor.GoToNextSibling() {
				didVisitChildren = false
			} else if cursor.GoToParent() {
				didVisitChildren = true
				indentLevel -= 1
			} else {
				break
			}
		} else {
			if isNamed {
				if needsNewline {
					_, err := writer.WriteString("\n")
					if err != nil {
						// handle error
					}
				}
				for i := 0; i < indentLevel; i++ {
					_, err := writer.WriteString("  ")
					if err != nil {
						// handle error
					}
				}
				start := node.StartPoint()
				end := node.EndPoint()
				fieldName := cursor.CurrentFieldName()
				if fieldName != "" {
					_, err := fmt.Fprintf(&writer, "%s: ", fieldName)
					if err != nil {
						// handle error
					}
				}
				_, err := fmt.Fprintf(&writer, "(%s [%d, %d] - [%d, %d]", node.Type(), start.Row, start.Column, end.Row, end.Column)
				if err != nil {
					// handle error
				}
				needsNewline = true
			}
			if cursor.GoToFirstChild() {
				didVisitChildren = false
				indentLevel += 1
			} else {
				didVisitChildren = true
			}
		}
	}
	return writer.String()
}
