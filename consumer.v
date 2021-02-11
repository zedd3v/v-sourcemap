module sourcemap

import json
import net.urllib
import os

struct SourceMap {
pub:
	version         int               [json: version]
	file            string            [json: file]
	source_root     string            [json: sourceRoot]
	sources         []string          [json: sources]
	sources_content []string          [json: sourcesContent]
	names           []json.RawMessage [json: names]
	mappings        string            [json: mappings]
	mappings        []mapping
}

struct V3 {
	SourceMap
pub:
	sections []Section [json: sections]
}

fn (m &SourceMap) parse(sourcemapURL string) ? {
	checkVersion(m.Version) ?

	sourceRootURL := net.urllib.URL
	{
	}
	if m.SourceRoot != '' {
		u := urllib.parse(m.SourceRoot) ?

		if u.IsAbs() {
			sourceRootURL = u
		}
	} else if sourcemapURL != '' {
		u := urllib.parse(sourcemapURL) ?

		if u.IsAbs() {
			u.Path = os.dir(u.Path)
			sourceRootURL = u
		}
	}

	for i, src in m.Sources {
		m.Sources[i] = m.abs_source(sourceRootURL, src)
	}

	mappings := parse_mappings(m.mappings) ?

	m.mappings = mappings
	// Free memory.
	m.mappings = ''

	return nil
}

fn (m &SourceMap) abs_source(root &urllib.URL, source string) string {
	if path.IsAbs(source) {
		return source
	}

	u := urllib.parse(source) ?
	if u.IsAbs() {
		return source
	}

	if root != nil {
		uu := root
		uu.Path = path.Join(u.Path, source)
		return uu.String()
	}

	if m.SourceRoot != '' {
		return path.Join(m.SourceRoot, source)
	}

	return source
}

fn (m &SourceMap) name(idx int) string {
	if idx >= m.Names.len {
		return ''
	}

	raw := m.Names[idx]
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
	offset    Offset     [json: offset]
	sourceMap &SourceMap [json: map]
}

struct Consumer {
	sourcemapURL string
	file         string
	sections     []Section
}

pub fn parse(sourcemapURL string, b []byte) ?&Consumer {
	v3 := json.decode(V3, string(b)) ?

	checkVersion(v3.Version) ?

	if v3.Sections.len == 0 {
		v3.Sections = append(v3.Sections, Section{
			Map: v3.sourceMap
		})
	}

	for _, s in v3.Sections {
		s.sourceMap.parse(sourcemapURL) ?
	}

	reverse(v3.Sections)
	return &Consumer{
		sourcemap_url: sourcemap_url
		file: v3.File
		sections: v3.Sections
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
pub fn (c &Consumer) source(genLine int, genColumn int) (string, string, int, int, bool) {
	for i in c.sections {
		s := &c.sections[i]
		if s.Offset.Line < genLine || (s.Offset.Line + 1 == genLine && s.Offset.Column <= genColumn) {
			genLine -= s.Offset.Line
			genColumn -= s.Offset.Column
			return c.psource(s.Map, genLine, genColumn)
		}
	}
	return
}

fn (c &Consumer) psource(m &SourceMap, genLine int, genColumn int) (string, string, int, int, bool) {
	mut source := ''
	mut name := ''

	i := sort.Search(m.mappings.len, fn (i int) bool {
		m := &m.mappings[i]
		if int(m.genLine) == genLine {
			return int(m.genColumn) >= genColumn
		}
		return int(m.genLine) >= genLine
	})

	// Mapping not found.
	if i == m.mappings.len {
		return '', '', 0, 0, false
	}

	mch := &m.mappings[i]

	// Fuzzy match.
	if int(mch.genLine) > genLine || int(mch.genColumn) > genColumn {
		if i == 0 {
			return '', '', 0, 0, false
		}
		mch = &m.mappings[i - 1]
	}

	if mch.sourcesInd >= 0 {
		source = m.Sources[mch.sourcesInd]
	}
	if mch.namesInd >= 0 {
		name = m.name(int(mch.namesInd))
	}

	return source, name, int(mch.sourceLine), int(mch.sourceColumn), true
}

// source_content returns the original source content for the source.
pub fn (c &Consumer) source_content(source string) string {
	for i in c.sections {
		s := &c.sections[i]
		for j, src in s.sourceMap.Sources {
			if src == source {
				if j < s.sourceMap.SourcesContent.len {
					return s.sourceMap.SourcesContent[j]
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
