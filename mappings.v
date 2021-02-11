module sourcemap

import io
import strings
import sourcemap.internal.base64vlq

type Func = fn (m &mappings) ?Func

struct Mapping {
	gen_line      int32
	gen_column    int32
	sources_ind   int32
	source_line   int32
	source_column int32
	names_ind     int32
}

struct Mappings {
	rd       &strings.Reader
	dec      base64vlq.Decoder
	has_name bool
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
	m.value.gen_line = 1
	m.value.source_line = 1

	m.parse() ?

	values := m.values
	m.values = nil
	return values
}

fn mappings_number(s string) int {
	return s.count(',') + s.count(';')
}

fn (m &mappings) parse() ? {
	next := parse_gen_col
	for {
		c, err := m.rd.ReadByte() or {
			if err == io.EOF {
				m.push_value()
				return
			}

			return error(err)
		}
		if err == io.EOF {
			m.push_value()
			return nil
		}

		match c {
			',' {
				m.push_value()
				next = parse_gen_col
			}
			';' {
				m.push_value()

				m.value.gen_line++
				m.value.gen_column = 0

				next = parse_gen_col
			}
			else {
				m.rd.UnreadByte() ?

				next = next(m) ?
			}
		}
	}
}

fn parse_gen_col(m &Mappings) ?func {
	n := m.dec.decode() ?

	m.value.gen_column += n
	return parse_sources_ind, nil
}

fn parse_sources_ind(m &Mappings) ?func {
	n := m.dec.decode() ?

	m.value.sources_ind += n
	return parse_source_line, nil
}

fn parse_source_line(m &Mappings) ?func {
	n := m.dec.decode() ?

	m.value.source_line += n
	return parse_source_col, nil
}

fn parse_source_col(m &Mappings) ?func {
	n := m.dec.decode() ?

	m.value.source_column += n
	return parse_names_ind, nil
}

fn parse_names_ind(m &Mappings) ?func {
	n := m.dec.decode() ?

	m.has_name = true
	m.value.names_ind += n
	return parse_gen_col, nil
}

fn (m &Mappings) push_value() {
	if m.value.source_line == 1 && m.value.source_column == 0 {
		return
	}

	if m.has_name {
		m.values = m.values << m.value
		m.has_name = false
	} else {
		m.values = m.values << Mapping{
			gen_line: m.value.gen_line
			gen_column: m.value.gen_column
			sources_ind: m.value.sources_ind
			source_line: m.value.source_line
			source_column: m.value.source_column
			names_ind: -1
		}
	}
}
