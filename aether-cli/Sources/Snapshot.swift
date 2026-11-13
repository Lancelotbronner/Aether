import AetherKit
import ArgumentParser
import Foundation
import SwiftData

/// Every group the CLI can `fetch`, in the order `Schema.swift` declares them.
/// A snapshot pins all seven rather than the three the entry names, because a
/// record that quietly omits `annotation` and `bookmark` — the rows an analyst
/// writes by hand — is the same under-reporting `delete` just learned not to do.
let snapshotGroups = ["program", "segment", "section", "symbol", "procedure", "annotation", "bookmark"]

/// `delete`'s plural words for the same seven kinds, so the summary line agrees
/// with every other count the CLI prints.
let snapshotPlurals = ["programs", "segments", "sections", "symbols", "procedures", "annotations", "bookmarks"]

private func groupRank(_ group: String) -> Int {
	snapshotGroups.firstIndex(of: group) ?? snapshotGroups.count
}

enum SnapshotError: LocalizedError {
	case unreadable(path: String, reason: String)

	var errorDescription: String? {
		switch self {
		case .unreadable(let path, let reason):
			return "Cannot read the snapshot at \(path): \(reason) — it has to be a file written by `snapshot`, a JSON array of objects of strings"
		}
	}
}

/// One pinned row: the group, then the model's own `fields()` — the same
/// structured source `describe()` renders and `fetch --json` prints, so a snapshot
/// cannot pin a field the CLI would not otherwise show. The discriminator is
/// `group` rather than `kind` because a `symbol` row already carries a `kind`
/// column of its own, and overwriting it would drop the distribution entry 17
/// reports.
struct SnapshotRow {
	let fields: [RowField]
	let values: [String: String]

	init(group: String, fields: [RowField]) {
		var built: [RowField] = [RowField(key: "group", value: group, text: group)]
		built += fields
		var map: [String: String] = ["group": group]
		for existing in fields {
			map[existing.key] = existing.value
		}
		self.fields = built
		self.values = map
	}

	/// A row read back out of a file has no model field order to keep, so its
	/// fields are rebuilt in key order; a file's JSON is only ever compared,
	/// never re-rendered, which is why hand-editing one stays legal.
	init(read values: [String: String]) {
		var built: [RowField] = []
		for entry in values.sorted(by: { a, b in a.key < b.key }) {
			built.append(RowField(key: entry.key, value: entry.value, text: entry.value))
		}
		self.fields = built
		self.values = values
	}

	var group: String { values["group"] ?? "?" }
	var name: String { values["name"] ?? "" }

	/// A child row already names the program it belongs to; a `program` row
	/// carries no such column, so its own name is the bucket.
	var program: String { values["program"] ?? name }
	var address: String { values["address"] ?? "" }

	/// The whole row in key order. Two rows cancel each other out exactly when
	/// this matches, which is why the order of lines in the file is irrelevant.
	var canonical: String {
		values
			.sorted(by: { a, b in a.key < b.key })
			.map { "\($0.key)=\($0.value)" }
			.joined(separator: " ")
	}

	/// Everything but the name. A renamed row and a deleted row look identical
	/// to a name diff, so the rest of the row is the only evidence a rename has.
	/// The `group` field survives the filter, so a rename cannot cross kinds.
	var withoutName: String {
		values
			.sorted(by: { a, b in a.key < b.key })
			.filter { entry in entry.key != "name" }
			.map { entry in "\(entry.key)=\(entry.value)" }
			.joined(separator: " ")
	}

	var bucket: String { "\(group) \(program) \(name)" }

	var json: String { jsonRow(fields) }
}

/// The rows a snapshot pins, in whatever order the store returns them; every
/// caller sorts through `compare(_:_:)` so a document's own row order never
/// reaches a file, and two runs of `snapshot` write the same bytes.
private func snapshotFields(in modelContext: ModelContext) throws -> [(group: String, fields: [RowField])] {
	var rows: [(group: String, fields: [RowField])] = []

	// `file` is the path the store happened to be opened through, which is not a
	// property of the program: pinning it would make every relative-vs-absolute
	// invocation report the program row as changed. Everything else stays,
	// including the per-kind counts — the numbers this record exists to pin.
	for program in try modelContext.fetch(FetchDescriptor<BinaryModel>()) {
		rows.append((group: "program", fields: program.fields().filter { existing in existing.key != "file" }))
	}
	for segment in try modelContext.fetch(FetchDescriptor<SegmentModel>()) {
		rows.append((group: "segment", fields: segment.fields()))
	}
	for section in try modelContext.fetch(FetchDescriptor<SectionModel>()) {
		rows.append((group: "section", fields: section.fields()))
	}
	for symbol in try modelContext.fetch(FetchDescriptor<SymbolModel>()) {
		rows.append((group: "symbol", fields: symbol.fields()))
	}
	for procedure in try modelContext.fetch(FetchDescriptor<ProcedureModel>()) {
		rows.append((group: "procedure", fields: procedure.fields()))
	}
	for annotation in try modelContext.fetch(FetchDescriptor<AnnotationModel>()) {
		rows.append((group: "annotation", fields: annotation.fields()))
	}
	for bookmark in try modelContext.fetch(FetchDescriptor<BookmarkModel>()) {
		rows.append((group: "bookmark", fields: bookmark.fields()))
	}
	return rows
}

// Two rows that differ only in which bucket they land in are still two rows of
// the same kind, so both groupings go through one helper rather than a per-call
// dictionary idiom.
private func bucketed(_ rows: [SnapshotRow], on key: (SnapshotRow) -> String) -> [String: [SnapshotRow]] {
	var out: [String: [SnapshotRow]] = [:]
	for row in rows {
		var entries = out[key(row)] ?? []
		entries.append(row)
		out[key(row)] = entries
	}
	return out
}

private func compare(_ a: SnapshotRow, _ b: SnapshotRow) -> Bool {
	if groupRank(a.group) != groupRank(b.group) {
		return groupRank(a.group) < groupRank(b.group)
	}
	if a.program != b.program {
		return a.program < b.program
	}
	if a.name != b.name {
		return a.name < b.name
	}
	if a.address != b.address {
		return a.address < b.address
	}
	return a.json < b.json
}

struct Change {
	enum Kind: String {
		case added
		case removed
		case renamed
		case moved
		case changed
	}

	var kind: Kind
	var group: String
	var name: String
	var line: String
}

private func diff(old: [SnapshotRow], new: [SnapshotRow]) -> (unchanged: Int, changes: [Change]) {
	// Identical rows cancel first, on the whole row rather than on a name, so the
	// 15052 rows that did not move cost a dictionary lookup and never pair up.
	var counts: [String: Int] = [:]
	for row in new {
		counts[row.canonical, default: 0] += 1
	}
	var unmatchedOld: [SnapshotRow] = []
	var unmatchedNew: [SnapshotRow] = []
	var unchanged = 0
	for row in old {
		if counts[row.canonical, default: 0] > 0 {
			counts[row.canonical, default: 0] -= 1
			unchanged += 1
		} else {
			unmatchedOld.append(row)
		}
	}
	for row in new {
		if counts[row.canonical, default: 0] > 0 {
			counts[row.canonical, default: 0] -= 1
			unmatchedNew.append(row)
		}
	}

	var changes: [Change] = []

	func label(_ row: SnapshotRow) -> String {
		row.name.isEmpty ? row.group : "\(row.group) \(row.name)"
	}

	func place(_ row: SnapshotRow) -> String {
		row.address.isEmpty ? "" : " @\(row.address)"
	}

	func shown(_ name: String, _ text: String) -> String {
		guard !text.isEmpty else {
			return "\"\""
		}
		return name == "address" ? "@\(text)" : text
	}

	func nameOrEmpty(_ row: SnapshotRow) -> String {
		row.name.isEmpty ? "\"\"" : row.name
	}

	// What is left stands on one side only, and is matched on `name` inside its
	// group and program: `#Unique<ProcedureModel>([\.symbol])` means renumbering
	// an address really is a remove plus an add to the store, so matching on
	// anything else would report every moved function as two changes.
	let byOld = bucketed(unmatchedOld, on: { row in row.bucket })
	let byNew = bucketed(unmatchedNew, on: { row in row.bucket })

	// The rows whose bucket has no counterpart on the other side are collected
	// across every bucket before being paired, because a rename is exactly the
	// case where the two halves land in different buckets.
	var spareOld: [SnapshotRow] = []
	var spareNew: [SnapshotRow] = []

	for bucket in Array(Set(byOld.keys).union(byNew.keys)).sorted() {
		// Both sides arrive in snapshot order, so a bucket whose name repeats
		// pairs by address rather than by whatever order SwiftData returned.
		let olds = byOld[bucket] ?? []
		let news = byNew[bucket] ?? []

		for index in 0..<max(olds.count, news.count) {
			guard index < olds.count, index < news.count else {
				if index < olds.count {
					spareOld.append(olds[index])
				} else {
					spareNew.append(news[index])
				}
				continue
			}
			let before = olds[index]
			let after = news[index]
			var differs: [(name: String, before: String, after: String)] = []
			for name in Array(Set(before.values.keys).union(after.values.keys)).sorted() {
				let left = before.values[name] ?? ""
				let right = after.values[name] ?? ""
				if left != right {
					differs.append((name: name, before: left, after: right))
				}
			}
			if differs.isEmpty {
				unchanged += 1
				continue
			}
			if differs.count == 1, differs[0].name == "address" {
				changes.append(Change(
					kind: .moved,
					group: before.group,
					name: before.name,
					line: "moved \(label(before)) @\(before.address) -> @\(after.address)"))
				continue
			}
			let detail = differs.map { entry in
				"\(entry.name) \(shown(entry.name, entry.before)) -> \(shown(entry.name, entry.after))"
			}.joined(separator: ", ")
			changes.append(Change(
				kind: .changed,
				group: before.group,
				name: before.name,
				line: "changed \(label(before)) — \(detail)"))
		}
	}

	// A vanished row and an appeared row whose every other field agree: the
	// only evidence a rename has, and the case a count-based diff gets wrong
	// twice over — a `removed` plus an `added` for what is one edit, and a
	// `renamed` for what is two edits if the rest of the row goes unchecked.
	let oldByRest = bucketed(spareOld, on: { row in row.withoutName })
	let newByRest = bucketed(spareNew, on: { row in row.withoutName })
	var restOld: [SnapshotRow] = []
	var restNew: [SnapshotRow] = []
	for rest in Array(Set(oldByRest.keys).union(newByRest.keys)).sorted() {
		let oldsHere = oldByRest[rest] ?? []
		let newsHere = newByRest[rest] ?? []
		for index in 0..<max(oldsHere.count, newsHere.count) {
			guard index < oldsHere.count, index < newsHere.count else {
				if index < oldsHere.count {
					restOld.append(oldsHere[index])
				} else {
					restNew.append(newsHere[index])
				}
				continue
			}
			let before = oldsHere[index]
			let after = newsHere[index]
			changes.append(Change(
				kind: .renamed,
				group: before.group,
				name: after.name,
				line: "renamed \(before.group) \(nameOrEmpty(before)) -> \(nameOrEmpty(after))\(place(before))"))
		}
	}
	for row in restOld {
		changes.append(Change(kind: .removed, group: row.group, name: row.name, line: "removed \(label(row))\(place(row))"))
	}
	for row in restNew {
		changes.append(Change(kind: .added, group: row.group, name: row.name, line: "added \(label(row))\(place(row))"))
	}

	changes.sort { a, b in
		if groupRank(a.group) != groupRank(b.group) {
			return groupRank(a.group) < groupRank(b.group)
		}
		if a.name != b.name {
			return a.name < b.name
		}
		if a.kind != b.kind {
			return a.kind.rawValue < b.kind.rawValue
		}
		return a.line < b.line
	}
	return (unchanged, changes)
}

struct SnapshotCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "snapshot",
		abstract: "Pins every row of a project to a file, keyed by stable name.")

	@OptionGroup var aether: AetherOptions

	@Option(help: "File to write. Without it the rows go to stdout and the summary line is suppressed, so a redirected run is a file `changes` can read")
	var out: String?

	mutating func run() async throws {
		let modelContext = try aether.backgroundContext()
		var rows: [SnapshotRow] = []
		for entry in try snapshotFields(in: modelContext) {
			rows.append(SnapshotRow(group: entry.group, fields: entry.fields))
		}
		rows.sort(by: compare)

		let text = jsonRows(rows.map { row in row.json })
		guard let out else {
			print(text)
			return
		}
		// `--dry-run` is a no-op rather than a way to skip the write: the flag
		// guards saving the store, and this command changes no store rows. The file
		// is the command's output, so suppressing it would leave nothing at all.
		// The trailing newline is what makes a redirected run and `--out` write
		// the same bytes: `print` adds one, `write` would not, and a file whose
		// last line is unterminated reads differently to `tail` and `diff`.
		try (text + "\n").write(to: URL(filePath: out, directoryHint: .notDirectory), atomically: true, encoding: .utf8)

		// The per-kind counts come because `75 rows` cannot say that the 14
		// procedures a detector run owes are among them, which is what a harness
		// reads this file for.
		var tallied: [String: Int] = [:]
		for row in rows {
			tallied[row.group, default: 0] += 1
		}
		var parts: [String] = []
		for index in 0..<snapshotGroups.count {
			guard let count = tallied[snapshotGroups[index]], count > 0 else { continue }
			parts.append("\(count) " + snapshotPlurals[index])
		}
		let line = "Snapshot \(rows.count) rows to \(out)"
		guard !parts.isEmpty else {
			print(line)
			return
		}
		print("\(line) — \(parts.joined(separator: ", "))")
	}
}

struct ChangesCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "changes",
		abstract: "Reports what changed in a project since a snapshot, matched on stable names.")

	@OptionGroup var aether: AetherOptions

	@OptionGroup var pageOptions: FetchOptions

	@Flag(help: "Exit non-zero when the project does not match the snapshot")
	var failChanged = false

	@Argument(help: "A file written by `snapshot`")
	var snapshot: String

	mutating func run() async throws {
		let modelContext = try aether.backgroundContext()
		let path = URL(filePath: snapshot, directoryHint: .notDirectory)
		var pinned: [[String: String]]
		do {
			pinned = try JSONDecoder().decode([[String: String]].self, from: try Data(contentsOf: path))
		} catch {
			throw SnapshotError.unreadable(path: snapshot, reason: error.localizedDescription)
		}

		// `group` is the field that says which kind of row a pinned row is, and
		// every other JSON this CLI prints decodes just as well without it — so
		// a `fetch --json` dump passed by mistake would otherwise report every
		// one of its rows as both gone and new.
		for row in pinned where row["group"] == nil {
			throw SnapshotError.unreadable(path: snapshot, reason: "a row has no \"group\" field")
		}

		var old = pinned.map { SnapshotRow(read: $0) }
		var current: [SnapshotRow] = []
		for entry in try snapshotFields(in: modelContext) {
			current.append(SnapshotRow(group: entry.group, fields: entry.fields))
		}
		old.sort(by: compare)
		current.sort(by: compare)
		let result = diff(old: old, new: current)
		let changes = result.changes

		// The verdict line is never paged: its whole point is to agree with the
		// file whether or not the terminal saw every row, so a script reads one
		// line rather than counting a page.
		var tallied: [String: Int] = [:]
		for change in changes {
			tallied[change.kind.rawValue, default: 0] += 1
		}
		var counts: [String] = []
		for name in ["added", "removed", "renamed", "moved", "changed"] {
			guard let count = tallied[name], count > 0 else { continue }
			counts.append("\(count) " + name)
		}
		print(changes.isEmpty
			? "Differences: 0 of \(old.count) pinned rows — the project matches the snapshot"
			: "Differences: \(changes.count) of \(old.count) pinned rows — \(counts.joined(separator: ", "))")

		// The page group is entry 23's, shared with every `fetch`: a diff over a
		// big program is the one report here that can run past a terminal, and
		// paging it is what makes `--all` the way to get the whole thing into a
		// file.
		let offset = min(pageOptions.offset ?? 0, changes.count)
		if let limit = pageOptions.pageLimit() {
			guard limit >= 0 else { throw FindError.negativeLimit }
			if limit > 0 {
				let window = Array(changes.dropFirst(offset)).prefix(limit)
				for change in window {
					print(change.line)
				}
				let printed = offset + window.count
				if printed < changes.count {
					print("… \(changes.count - printed) more — --all for every difference, --offset \(printed) for the next page")
				}
			}
		} else {
			for change in changes.dropFirst(offset) {
				print(change.line)
			}
		}

		// The entry asks for a non-zero exit rather than a line a script has to
		// grep. A thrown `ExitCode` prints nothing of its own, which is how `--strict`
		// already fails, so the verdict line stays the only thing to read.
		guard !failChanged || changes.isEmpty else {
			throw ExitCode(1)
		}
	}
}
