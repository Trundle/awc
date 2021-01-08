// This can be replaced with go:embed in Go 1.16

// +build ignore

package main

import (
	"bytes"
	"encoding/hex"
	"io"
	"io/ioutil"
	"os"
	"path/filepath"
	"text/template"
)

const fileTemplate = `
package main

import "encoding/hex"

var {{ .Name }}Bytes, _ = hex.DecodeString("{{ .Contents }}")
var {{ .Name }} = string({{ .Name }}Bytes)
`

func main() {
	contents, err := ioutil.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}

	base := filepath.Base(os.Args[1])
	name := base[:len(base)-len(filepath.Ext(base))]

	tmpl, err := template.New("embed").Parse(fileTemplate)
	if err != nil {
		panic(err)
	}

	var buffer bytes.Buffer
	vars := struct {
		Name string
		Contents string
	}{name, hex.EncodeToString(contents)}
	err = tmpl.Execute(io.Writer(&buffer), vars)
	if err != nil {
		panic(err)
	}

	outPath := filepath.Join(filepath.Dir(os.Args[1]), "..", base + ".generated.go")
	ioutil.WriteFile(outPath, buffer.Bytes(), 0644)
}
