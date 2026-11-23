package core

import (
	"io"
	"os"
	"strings"
)

type keyValue struct {
	name, value string
	children    []keyValue
}

func (kv keyValue) child(key string) keyValue {
	for _, item := range kv.children {
		if strings.EqualFold(item.name, key) {
			return item
		}
	}
	return keyValue{}
}

func readVDF(path string) keyValue {
	f, err := os.Open(path)
	if err != nil {
		return keyValue{}
	}
	defer f.Close()

	const sizeLimit = 2 << 20
	data, err := io.ReadAll(io.LimitReader(f, sizeLimit+1))
	if err != nil || len(data) > sizeLimit {
		return keyValue{}
	}
	return parseVDF(string(data))
}

type vdfReader struct {
	rest string
}

func (r *vdfReader) token() (value string, kind byte) {
	for {
		r.rest = strings.TrimLeft(r.rest, " \t\r\n")
		if !strings.HasPrefix(r.rest, "//") {
			break
		}
		line := strings.IndexByte(r.rest, '\n')
		if line < 0 {
			r.rest = ""
			break
		}
		r.rest = r.rest[line+1:]
	}
	if r.rest == "" {
		return "", 0
	}
	switch r.rest[0] {
	case '{', '}':
		kind = r.rest[0]
		r.rest = r.rest[1:]
		return "", kind
	case '"':
		r.rest = r.rest[1:]
		var quoted strings.Builder
		for i := 0; i < len(r.rest); i++ {
			ch := r.rest[i]
			if ch == '"' {
				r.rest = r.rest[i+1:]
				return quoted.String(), 'v'
			}
			if ch == '\\' && i+1 < len(r.rest) && (r.rest[i+1] == '\\' || r.rest[i+1] == '"') {
				i++
				ch = r.rest[i]
			}
			quoted.WriteByte(ch)
		}
		r.rest = ""
		return "", '!'
	default:
		i := strings.IndexAny(r.rest, " \t\r\n{}\"")
		if i < 0 {
			i = len(r.rest)
		}
		value, r.rest = r.rest[:i], r.rest[i:]
		return value, 'v'
	}
}

func (r *vdfReader) table(depth int) ([]keyValue, bool) {
	if depth > 32 {
		return nil, false
	}
	var values []keyValue
	for {
		name, kind := r.token()
		if kind == 0 {
			return values, depth == 0
		}
		if kind == '}' {
			return values, depth != 0
		}
		if kind != 'v' {
			return nil, false
		}
		value, kind := r.token()
		entry := keyValue{name: name, value: value}
		if kind == '{' {
			var okay bool
			entry.children, okay = r.table(depth + 1)
			if !okay {
				return nil, false
			}
		} else if kind != 'v' {
			return nil, false
		}
		values = append(values, entry)
	}
}

func parseVDF(contents string) keyValue {
	reader := vdfReader{rest: strings.TrimPrefix(contents, "\uFEFF")}
	entries, ok := reader.table(0)
	if !ok {
		return keyValue{}
	}
	return keyValue{children: entries}
}
