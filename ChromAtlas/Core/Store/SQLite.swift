import Foundation
import SQLite3

/// Minimal, dependency-free SQLite wrapper (the system library ships with the R*Tree module enabled).
final class SQLiteDB {
    enum DBError: Error, CustomStringConvertible {
        case open(String), prepare(String), step(String)
        var description: String {
            switch self {
            case .open(let m): return "open: \(m)"
            case .prepare(let m): return "prepare: \(m)"
            case .step(let m): return "step: \(m)"
            }
        }
    }

    private(set) var handle: OpaquePointer?
    private let lock = NSRecursiveLock()

    init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        if sqlite3_open_v2(path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw DBError.open(String(cString: sqlite3_errmsg(handle)))
        }
        if !readOnly {
            try? execute("PRAGMA journal_mode=WAL;")
            try? execute("PRAGMA synchronous=NORMAL;")
        }
    }

    deinit { sqlite3_close_v2(handle) }

    var errorMessage: String { String(cString: sqlite3_errmsg(handle)) }

    func execute(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(err)
            throw DBError.step(msg)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DBError.prepare("\(errorMessage) — \(sql)")
        }
        return Statement(stmt!, db: self)
    }

    func transaction(_ body: () throws -> Void) throws {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    final class Statement {
        private let stmt: OpaquePointer
        private unowned let db: SQLiteDB

        fileprivate init(_ stmt: OpaquePointer, db: SQLiteDB) {
            self.stmt = stmt
            self.db = db
        }

        deinit { sqlite3_finalize(stmt) }

        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        @discardableResult
        func bind(_ values: [Any?]) -> Statement {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            for (i, v) in values.enumerated() {
                let idx = Int32(i + 1)
                switch v {
                case nil: sqlite3_bind_null(stmt, idx)
                case let x as Int: sqlite3_bind_int64(stmt, idx, Int64(x))
                case let x as Int64: sqlite3_bind_int64(stmt, idx, x)
                case let x as Double: sqlite3_bind_double(stmt, idx, x)
                case let x as Float: sqlite3_bind_double(stmt, idx, Double(x))
                case let x as String: sqlite3_bind_text(stmt, idx, x, -1, Statement.transient)
                case let x as Bool: sqlite3_bind_int(stmt, idx, x ? 1 : 0)
                default: sqlite3_bind_null(stmt, idx)
                }
            }
            return self
        }

        /// Runs to completion (for INSERT/UPDATE/DELETE).
        func run() throws {
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw DBError.step(db.errorMessage) }
            sqlite3_reset(stmt)
        }

        /// Iterates rows.
        func forEach(_ body: (Row) throws -> Void) throws {
            defer { sqlite3_reset(stmt) }
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { return }
                guard rc == SQLITE_ROW else { throw DBError.step(db.errorMessage) }
                try body(Row(stmt: stmt))
            }
        }
    }

    struct Row {
        let stmt: OpaquePointer
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func string(_ i: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, i) else { return "" }
            return String(cString: c)
        }
        func optionalDouble(_ i: Int32) -> Double? { isNull(i) ? nil : double(i) }
        func optionalInt(_ i: Int32) -> Int? { isNull(i) ? nil : int(i) }
        func optionalString(_ i: Int32) -> String? { isNull(i) ? nil : string(i) }
    }
}
