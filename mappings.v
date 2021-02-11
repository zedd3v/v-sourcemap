module sourcemap

import io
import strings
import sourcemap.internal.base64vlq

type Func = fn (m &mappings) ?Func

struct Mapping {
	genLine      int32
	genColumn    int32
	sourcesInd   int32
	sourceLine   int32
	sourceColumn int32
	namesInd     int32
}

struct Mappings {
	rd      &strings.Reader
	dec     base64vlq.Decoder
	hasName bool
mut:
	value  mapping
	values []mapping
}

fn parse_mappings(s string) ?[]Mapping {
	if s == '' {
		return error('sourcemap: mappings are empty')
	}

	rd := strings.new_reader(s)
	m := &Mappings{
		rd: rd
		dec: base64vlq.new_decoder(rd)
		values: make([]Mapping{}, 0, mappings_number(s))
	}
	m.value.genLine = 1
	m.value.sourceLine = 1

	m.parse() ?

	values := m.values
	m.values = nil
	return values
}

fn mappings_number(s string) int {
	return s.count(',') + s.count(';')
}

fn (m &mappings) parse() ? {
	next := parseGenCol
	for {
		c, err := m.rd.ReadByte() or {
			if err == io.EOF {
				m.pushValue()
				return
			}

			return error(err)
		}
		if err == io.EOF {
			m.pushValue()
			return nil
		}

		match c {
			',' {
				m.pushValue()
				next = parseGenCol
			}
			';' {
				m.pushValue()

				m.value.genLine++
				m.value.genColumn = 0

				next = parseGenCol
			}
			else {
				m.rd.UnreadByte() ?

				next = next(m) ?
			}
		}
	}
}

fn parse_gen_col(m &Mappings) ?func {
	n := m.dec.Decode() ?

	m.value.genColumn += n
	return parse_sources_ind, nil
}

fn parse_sources_ind(m &Mappings) ?func {
	n := m.dec.Decode() ?

	m.value.sourcesInd += n
	return parse_source_line, nil
}

fn parse_source_line(m &Mappings) ?func {
	n := m.dec.Decode() ?

	m.value.sourceLine += n
	return parse_source_col, nil
}

fn parse_source_col(m &Mappings) ?func {
	n := m.dec.Decode() ?

	m.value.sourceColumn += n
	return parse_names_ind, nil
}

fn parse_names_ind(m &Mappings) ?func {
	n := m.dec.Decode() ?

	m.hasName = true
	m.value.namesInd += n
	return parse_gen_col, nil
}

fn (m &Mappings) push_value() {
	if m.value.sourceLine == 1 && m.value.sourceColumn == 0 {
		return
	}

	if m.hasName {
		m.values = append(m.values, m.value)
		m.hasName = false
	} else {
		m.values = append(m.values, Mapping{
			genLine: m.value.genLine
			genColumn: m.value.genColumn
			sourcesInd: m.value.sourcesInd
			sourceLine: m.value.sourceLine
			sourceColumn: m.value.sourceColumn
			namesInd: -1
		})
	}
}
