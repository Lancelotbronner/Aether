import Foundation

/// One field of a model row, carrying both renderings so the human row and
/// `--json` cannot drift apart: `describe()` joins `text`, `--json` serialises
/// `key` / `value`.
struct RowField {
	/// Stable, lower-case JSON key — never a SwiftData column name.
	let key: String

	/// The value exactly as stored, which is what the JSON object prints once
	/// it is quoted and escaped.
	let value: String

	/// The exact fragment of the text row: `size=888`, `@1000006E8`,
	/// `51480 bytes`, `thin_test`. Positional fields carry the value alone,
	/// which is why the seven rows keep their existing shapes.
	let text: String
}

/// A `key=value` field.
func field(_ key: String, _ value: Any) -> RowField {
	let text = "\(value)"
	return RowField(key: key, value: text, text: "\(key)=\(escapeControl(text))")
}

/// A positional field: the text row prints the value with no key in front of
/// it. Used by the leading name of every row, and by the whole head of the
/// program row.
func head(_ key: String, _ value: Any) -> RowField {
	let text = "\(value)"
	return RowField(key: key, value: text, text: escapeControl(text))
}

/// A positional field followed by a unit word — only `program`'s
/// `51480 bytes` needs this, and the JSON value stays the bare count.
func head(_ key: String, _ value: Any, unit: String) -> RowField {
	let text = "\(value)"
	return RowField(key: key, value: text, text: "\(escapeControl(text)) \(unit)")
}

/// The `@<hex address>` field every child row leads with; keyed `address`.
func at(_ value: Any) -> RowField {
	let text = "\(value)"
	return RowField(key: "address", value: text, text: "@\(escapeControl(text))")
}

/// A row rendered as text from a field list: what `describe()` does with a
/// model's own `fields()`, and what a row altered by `--demangle` needs before
/// it is printed.
func render(_ fields: [RowField]) -> String {
	fields.map { $0.text }.joined(separator: " ")
}

/// A row as one JSON object.
func jsonRow(_ fields: [RowField]) -> String {
	"{" + fields.map { "\(escapeJSON($0.key)): \(escapeJSON($0.value))" }.joined(separator: ", ") + "}"
}

/// Rows as one JSON array, one object per line.
func jsonRows(_ rows: [String]) -> String {
	guard !rows.isEmpty else {
		return "[]"
	}
	return "[\n" + rows.joined(separator: ",\n") + "\n]"
}

/// A newline inside a stored value wraps a text row on to a second line — and
/// silently breaks the one-row-per-line invariant a script parses — so control
/// characters never reach either rendering raw.
private func escapeControl(_ text: String) -> String {
	var out = ""
	for character in text {
		out += escapeControl(character)
	}
	return out
}

private func escapeControl(_ character: Character) -> String {
	switch character {
	case "\u{08}":
		return "\\b"
	case "\u{0C}":
		return "\\f"
	case "\n":
		return "\\n"
	case "\r":
		return "\\r"
	case "\t":
		return "\\t"
	default:
		guard let code = character.utf16.first, code < 0x20 else {
			return String(character)
		}
		return String(format: "\\u%04X", code)
	}
}

/// JSON strings: the control escaping above plus the two characters JSON
/// cannot carry inside a string.
private func escapeJSON(_ text: String) -> String {
	var out = "\""
	for character in text {
		switch character {
		case "\"":
			out += "\\\""
		case "\\":
			out += "\\\\"
		default:
			out += escapeControl(character)
		}
	}
	return out + "\""
}
