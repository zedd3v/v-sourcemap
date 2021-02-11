module sourcemap

import json
import net.urllib
import os

struct SourceMap {
pub:
	version         int               [json: version]
	file            string            [json: file]
	source_root     string            [json: source_root]
	sources         []string          [json: sources]
	sources_content []string          [json: sources_content]
	names           []json.RawMessage [json: names]
	mappings        string            [json: mappings]
	mappings        []mapping
}

struct V3 {
	SourceMap
pub:
	sections []Section [json: sections]
}

fn (m &SourceMap) parse(source_map_url string) ? {
	check_version(m.Version) ?

	source_root_url := net.urllib.URL
	{
	}
	if m.source_root != '' {
		u := urllib.parse(m.source_root) ?

		if u.is_abs() {
			source_root_url = u
		}
	} else if source_map_url != '' {
		u := urllib.parse(source_map_url) ?

		if u.is_abs() {
			u.path = os.dir(u.Path)
			source_root_url = u
		}
	}

	for i, src in m.Sources {
		m.Sources[i] = m.abs_source(source_root_url, src)
	}

	mappings := parse_mappings(m.mappings) ?

	m.mappings = mappings
	// Free memory.
	m.mappings = ''

	return nil
}

fn (m &SourceMap) abs_source(root &urllib.URL, source string) string {
	if os.is_abs_path(source) {
		return source
	}

	u := urllib.parse(source) ?
	if u.is_abs() {
		return source
	}

	if root != nil {
		uu := root
		uu.path = os.join_path(u.path, source)
		return uu.String()
	}

	if m.source_root != '' {
		return os.join_path(m.source_root, source)
	}

	return source
}

fn (m &SourceMap) name(idx int) string {
	if idx >= m.names.len {
		return ''
	}

	raw := m.names[idx]
	if raw.len == 0 {
		return ''
	}

	if raw[0] == '"' && raw[raw.len - 1] == '"' {
		mut str := json.decode(string, raw) or { }
	}

	return string(raw)
}

struct Offset {
pub:
	line   int [json: line]
	column int [json: column]
}

struct Section {
pub:
	offset     Offset     [json: offset]
	source_map &SourceMap [json: map]
}

struct Consumer {
	source_map_url string
	file           string
	sections       []Section
}

pub fn parse(source_map_url string, b []byte) ?&Consumer {
	v3 := json.decode(V3, string(b)) ?

	check_version(v3.Version) ?

	if v3.sections.len == 0 {
		v3.sections = append(v3.sections, Section{
			source_map: v3.SourceMap
		})
	}

	for _, s in v3.sections {
		s.source_map.parse(source_map_url) ?
	}

	reverse(v3.sections)
	return &Consumer{
		sourcemap_url: sourcemap_url
		file: v3.file
		sections: v3.sections
	}, nil
}

pub fn (c &Consumer) sourcemap_url() string {
	return c.sourcemap_url
}

// file returns an optional name of the generated code
// that this source map is associated with.
pub fn (c &Consumer) file() string {
	return c.file
}

// source returns the original source, name, line, and column information
// for the generated source's line and column positions.
pub fn (c &Consumer) source(gen_line int, genColumn int) (string, string, int, int, bool) {
	for i in c.sections {
		s := &c.sections[i]
		if s.offset.Line < gen_line
			|| (s.offset.Line + 1 == gen_line && s.offset.Column <= genColumn) {
			gen_line -= s.offset.Line
			genColumn -= s.offset.Column
			return c.psource(s.Map, gen_line, genColumn)
		}
	}
	return
}

fn (c &Consumer) psource(m &SourceMap, gen_line int, gen_column int) (string, string, int, int, bool) {
	mut source := ''
	mut name := ''

	i := sort.Search(m.mappings.len, fn (i int) bool {
		m := &m.mappings[i]
		if int(m.gen_line) == gen_line {
			return int(m.gen_column) >= gen_column
		}
		return int(m.gen_line) >= gen_line
	})

	// Mapping not found.
	if i == m.mappings.len {
		return '', '', 0, 0, false
	}

	mch := &m.mappings[i]

	// Fuzzy match.
	if int(mch.gen_line) > gen_line || int(mch.gen_column) > gen_column {
		if i == 0 {
			return '', '', 0, 0, false
		}
		mch = &m.mappings[i - 1]
	}

	if mch.sources_ind >= 0 {
		source = m.sources[mch.sources_ind]
	}
	if mch.names_ind >= 0 {
		name = m.name(int(mch.names_ind))
	}

	return source, name, int(mch.source_line), int(mch.source_column), true
}

// source_content returns the original source content for the source.
pub fn (c &Consumer) source_content(source string) string {
	for i in c.sections {
		s := &c.sections[i]
		for j, src in s.source_map.sources {
			if src == source {
				if j < s.source_map.sources_content.len {
					return s.source_map.sources_content[j]
				}
				break
			}
		}
	}
	return ''
}

fn check_version(version int) ? {
	if version == 3 || version == 0 {
		return
	}
	return error('sourcemap: got version=$version, but only 3rd version is supported')
}

fn reverse(ss []Section) {
	last := ss.len - 1
	for i := 0; i < ss.len / 2; i++ {
		ss[i], ss[last - i] = ss[last - i], ss[i]
	}
}
