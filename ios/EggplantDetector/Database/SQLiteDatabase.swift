import Foundation
import SQLite3

final class SQLiteDatabase {
    let url: URL
    private var handle: OpaquePointer?

    init(url: URL) throws {
        self.url = url
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database."
            throw SQLiteError.openFailed(message)
        }
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        guard let handle else {
            throw SQLiteError.openFailed("Database handle is unavailable.")
        }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorMessage)
            throw SQLiteError.executionFailed(message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        guard let handle else {
            throw SQLiteError.openFailed("Database handle is unavailable.")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.executionFailed(String(cString: sqlite3_errmsg(handle)))
        }
        return SQLiteStatement(statement: statement)
    }

    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var lastInsertedRowID: Int64 {
        guard let handle else { return 0 }
        return sqlite3_last_insert_rowid(handle)
    }
}

final class SQLiteStatement {
    private let statement: OpaquePointer?

    init(statement: OpaquePointer?) {
        self.statement = statement
    }

    deinit {
        sqlite3_finalize(statement)
    }

    @discardableResult
    func step() throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.executionFailed("SQLite step failed with code \(result).")
        }
        return result
    }

    func bind(_ value: String?, at index: Int32) throws {
        if let value {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
                throw SQLiteError.bindFailed
            }
        } else {
            try bindNull(at: index)
        }
    }

    func bind(_ value: Int64?, at index: Int32) throws {
        if let value {
            guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
                throw SQLiteError.bindFailed
            }
        } else {
            try bindNull(at: index)
        }
    }

    func bind(_ value: Double?, at index: Int32) throws {
        if let value {
            guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
                throw SQLiteError.bindFailed
            }
        } else {
            try bindNull(at: index)
        }
    }

    func bind(_ value: Bool?, at index: Int32) throws {
        if let value {
            try bind(value ? Int64(1) : Int64(0), at: index)
        } else {
            try bindNull(at: index)
        }
    }

    private func bindNull(at index: Int32) throws {
        guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
            throw SQLiteError.bindFailed
        }
    }

    func columnString(_ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(statement, index)
    }

    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    func columnBool(_ index: Int32) -> Bool {
        sqlite3_column_int(statement, index) != 0
    }

    func isNull(_ index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }
}

enum SQLiteError: LocalizedError {
    case openFailed(String)
    case executionFailed(String)
    case bindFailed

    var errorDescription: String? {
        switch self {
        case let .openFailed(message), let .executionFailed(message):
            return message
        case .bindFailed:
            return "Could not bind a SQLite statement value."
        }
    }
}
