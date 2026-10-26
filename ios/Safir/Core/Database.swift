import Foundation
import Security
// SQLCipher (Podfile) replaces the system SQLite; the fallback keeps unit builds without the pod working.
#if canImport(SQLCipher)
import SQLCipher
#else
import SQLite3
#endif

enum SQLValue {
    case int(Int64)
    case text(String)
    case blob(Data)
    case null
}

struct DatabaseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// One row of a query result (column indexes as in the SELECT).
struct Row {
    fileprivate let stmt: OpaquePointer

    func int(_ index: Int32) -> Int64 { sqlite3_column_int64(stmt, index) }
    func isNull(_ index: Int32) -> Bool { sqlite3_column_type(stmt, index) == SQLITE_NULL }

    func text(_ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    func blob(_ index: Int32) -> Data? {
        guard let ptr = sqlite3_column_blob(stmt, index) else { return isNull(index) ? nil : Data() }
        return Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, index)))
    }
}

/// Local store: Signal protocol state, chats and messages. Plain SQLite (the system library)
/// guarded by one recursive lock - libsignal's store callbacks are synchronous and may re-enter
/// while a transaction is open. The file sits in the App Group container so the Notification
/// Service Extension can decrypt with the same sessions, and uses the
/// "until first unlock" data-protection class so that extension can open it on a locked phone.
final class Database {
    static let shared: Database = {
        do {
            return try Database(url: Database.defaultURL())
        } catch {
            fatalError("Cannot open the local database: \(error)")
        }
    }()

    static let appGroup = "group.tj.safir.messenger"

    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var transactionDepth = 0

    /// The active account's database (Keychain account_id) - each account on the phone has its
    /// own file (Accounts.swift), so chats and Signal sessions never mix.
    static func defaultURL() throws -> URL {
        try url(forAccount: Keychain.get("account_id"))
    }

    /// The account that was signed in before multi-account existed keeps the original file;
    /// every other account gets "safir-<id>.sqlite".
    static func url(forAccount id: String?) throws -> URL {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try fm.createDirectory(at: base, withIntermediateDirectories: true,
                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var legacy = Keychain.get("db_legacy_owner")
        if legacy == nil, let id {
            Keychain.set(id, for: "db_legacy_owner")
            legacy = id
        }
        guard let id, id != legacy else { return base.appendingPathComponent("safir.sqlite") }
        return base.appendingPathComponent("safir-\(id).sqlite")
    }

    init(url: URL) throws {
        try open(url)
    }

    private func open(_ url: URL) throws {
        try openRaw(url)
        if cipherAvailable {
            let key = Self.cipherKey()
            try applyKey(key)
            if !readable() {
                // A file from before encryption (or from a build without SQLCipher): re-encrypt it once.
                sqlite3_close(handle)
                handle = nil
                try Self.encryptPlaintext(at: url, key: key)
                try openRaw(url)
                try applyKey(key)
                guard readable() else { throw DatabaseError(message: "encrypted database cannot be read") }
            }
        } else {
            AppLog.write("SQLCipher missing: the local database is not encrypted")
        }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: url.path)
        sqlite3_busy_timeout(handle, 5000)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try Schema.migrate(self)
    }

    private func openRaw(_ url: URL) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            throw DatabaseError(message: "open failed: \(String(cString: sqlite3_errmsg(handle)))")
        }
    }

    // MARK: SQLCipher (Android keeps Room in SQLCipher too)

    /// "PRAGMA cipher_version" answers only when the SQLCipher library is the one linked.
    private var cipherAvailable: Bool {
        ((try? first("PRAGMA cipher_version") { $0.text(0) }) ?? nil)?.isEmpty == false
    }

    /// Raw key + salt, like Signal-iOS. The first 32 bytes stay plain (the SQLite header), so iOS
    /// still sees a database file and doesn't kill the app for holding a lock on an unknown file
    /// in the shared container (0xdead10cc); the salt then has to live outside the file - here.
    private func applyKey(_ hex: String) throws {
        try execute("PRAGMA key = \"x'\(hex)'\"")
        try execute("PRAGMA cipher_plaintext_header_size = 32")
    }

    private func readable() -> Bool {
        (try? first("SELECT count(*) FROM sqlite_master") { $0.int(0) }) != nil
    }

    /// 32-byte key + 16-byte salt as hex, made once and shared with the notification extension
    /// through the Keychain group (after first unlock, this device only).
    private static func cipherKey() -> String {
        if let hex = Keychain.get("db_cipher_key"), hex.count == 96 { return hex }
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        Keychain.set(hex, for: "db_cipher_key")
        return hex
    }

    /// sqlcipher_export into a new encrypted file, then swap it in.
    private static func encryptPlaintext(at url: URL, key: String) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".enc")
        remove(url: tmp)
        var plain: OpaquePointer?
        guard sqlite3_open_v2(url.path, &plain, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(plain)
            throw DatabaseError(message: "cannot open the old database")
        }
        let steps = [
            "PRAGMA wal_checkpoint(TRUNCATE)",
            "ATTACH DATABASE '\(tmp.path.replacingOccurrences(of: "'", with: "''"))' AS encrypted KEY \"x'\(key)'\"",
            "PRAGMA encrypted.cipher_plaintext_header_size = 32",
            "SELECT sqlcipher_export('encrypted')",
            "DETACH DATABASE encrypted",
        ]
        for sql in steps where sqlite3_exec(plain, sql, nil, nil, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(plain))
            sqlite3_close(plain)
            remove(url: tmp)
            throw DatabaseError(message: "encrypting the database failed: \(message)")
        }
        sqlite3_close(plain)
        remove(url: url)
        try FileManager.default.moveItem(at: tmp, to: url)
        AppLog.write("Local database encrypted (SQLCipher)")
    }

    /// Switch the one shared connection to another account's file (every store holds this same
    /// object, so they all follow). Callers stop the message pipeline first.
    func reopen(url: URL) throws {
        try locked {
            sqlite3_close(handle)
            handle = nil
            transactionDepth = 0
            try open(url)
        }
    }

    /// A signed-out account's file, with its WAL side files.
    static func remove(url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String, _ args: [SQLValue] = []) throws {
        try locked {
            let stmt = try prepare(sql, args)
            defer { sqlite3_finalize(stmt) }
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw lastError("step") }
        }
    }

    func query<T>(_ sql: String, _ args: [SQLValue] = [], _ map: (Row) throws -> T) throws -> [T] {
        try locked {
            let stmt = try prepare(sql, args)
            defer { sqlite3_finalize(stmt) }
            var out: [T] = []
            while true {
                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { break }
                guard rc == SQLITE_ROW else { throw lastError("step") }
                out.append(try map(Row(stmt: stmt)))
            }
            return out
        }
    }

    func first<T>(_ sql: String, _ args: [SQLValue] = [], _ map: (Row) throws -> T) throws -> T? {
        try query(sql, args, map).first
    }

    /// Rows changed by the last INSERT/UPDATE/DELETE on this connection.
    var changes: Int { Int(sqlite3_changes(handle)) }

    /// Nested calls join the outer transaction.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try locked {
            if transactionDepth > 0 {
                return try body()
            }
            try execute("BEGIN IMMEDIATE")
            transactionDepth += 1
            do {
                let result = try body()
                transactionDepth -= 1
                try execute("COMMIT")
                return result
            } catch {
                transactionDepth -= 1
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func prepare(_ sql: String, _ args: [SQLValue]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw lastError("prepare")
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            let rc: Int32
            switch arg {
            case .int(let v):
                rc = sqlite3_bind_int64(stmt, index, v)
            case .text(let v):
                rc = sqlite3_bind_text(stmt, index, v, -1, transient)
            case .blob(let v):
                rc = v.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, index, buf.baseAddress, Int32(buf.count), transient)
                }
            case .null:
                rc = sqlite3_bind_null(stmt, index)
            }
            if rc != SQLITE_OK {
                sqlite3_finalize(stmt)
                throw lastError("bind")
            }
        }
        return stmt
    }

    private func lastError(_ stage: String) -> DatabaseError {
        DatabaseError(message: "\(stage): \(String(cString: sqlite3_errmsg(handle)))")
    }
}

// MARK: - Small key/value table for app metadata

extension Database {
    func string(_ key: String) -> String? {
        (try? first("SELECT value FROM kv WHERE key = ?", [.text(key)]) { $0.text(0) }) ?? nil
    }

    func int(_ key: String) -> Int64? {
        string(key).flatMap { Int64($0) }
    }

    func set(_ value: String?, for key: String) {
        if let value {
            try? execute("INSERT OR REPLACE INTO kv(key, value) VALUES(?, ?)", [.text(key), .text(value)])
        } else {
            try? execute("DELETE FROM kv WHERE key = ?", [.text(key)])
        }
    }

    func set(_ value: Int64?, for key: String) {
        set(value.map { String($0) }, for: key)
    }
}

extension SQLValue {
    static func optText(_ value: String?) -> SQLValue { value.map { .text($0) } ?? .null }
    static func optInt(_ value: Int?) -> SQLValue { value.map { .int(Int64($0)) } ?? .null }
    static func bool(_ value: Bool) -> SQLValue { .int(value ? 1 : 0) }
}
