import Foundation

/// Local schema, versioned with PRAGMA user_version. Each step runs once, in order; never edit a
/// shipped step - append a new one. Times are Unix milliseconds.
enum Schema {
    private static let steps: [[String]] = [
        // 1: Signal protocol state (mirrors Android's Ratchet*/GroupSenderKey* Room tables) plus
        // chats, members, users and messages.
        [
            "CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT)",

            """
            CREATE TABLE sig_identity (
                user_id TEXT NOT NULL, device_id INTEGER NOT NULL, identity_key BLOB NOT NULL,
                trusted_at INTEGER NOT NULL, change_pending INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (user_id, device_id))
            """,
            "CREATE TABLE sig_prekey (id INTEGER PRIMARY KEY, record BLOB NOT NULL)",
            "CREATE TABLE sig_signed_prekey (id INTEGER PRIMARY KEY, record BLOB NOT NULL)",
            "CREATE TABLE sig_kyber_prekey (id INTEGER PRIMARY KEY, record BLOB NOT NULL)",
            """
            CREATE TABLE sig_kyber_base_key (
                kyber_id INTEGER NOT NULL, signed_id INTEGER NOT NULL, base_key BLOB NOT NULL,
                PRIMARY KEY (kyber_id, signed_id, base_key))
            """,
            """
            CREATE TABLE sig_session (
                user_id TEXT NOT NULL, device_id INTEGER NOT NULL, record BLOB NOT NULL,
                PRIMARY KEY (user_id, device_id))
            """,
            """
            CREATE TABLE sig_sender_key (
                user_id TEXT NOT NULL, device_id INTEGER NOT NULL, distribution_id TEXT NOT NULL,
                record BLOB NOT NULL, PRIMARY KEY (user_id, device_id, distribution_id))
            """,
            """
            CREATE TABLE sig_group_meta (
                chat_id TEXT PRIMARY KEY, distribution_id TEXT NOT NULL, key_version INTEGER NOT NULL)
            """,

            """
            CREATE TABLE users (
                id TEXT PRIMARY KEY, username TEXT NOT NULL DEFAULT '', email TEXT,
                full_name TEXT NOT NULL DEFAULT '', avatar_url TEXT, bio TEXT,
                is_online INTEGER NOT NULL DEFAULT 0, last_seen TEXT,
                is_bot INTEGER NOT NULL DEFAULT 0, is_premium INTEGER NOT NULL DEFAULT 0)
            """,
            """
            CREATE TABLE chats (
                id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '', avatar_url TEXT,
                is_group INTEGER NOT NULL DEFAULT 0, is_channel INTEGER NOT NULL DEFAULT 0,
                is_bot INTEGER NOT NULL DEFAULT 0, partner_id TEXT,
                last_message TEXT, last_message_time INTEGER NOT NULL DEFAULT 0,
                last_sender_id TEXT, last_status INTEGER NOT NULL DEFAULT 1,
                last_is_read INTEGER NOT NULL DEFAULT 0, unread_count INTEGER NOT NULL DEFAULT 0,
                group_key_version INTEGER NOT NULL DEFAULT 1, ttl_seconds INTEGER NOT NULL DEFAULT 0,
                is_secret INTEGER NOT NULL DEFAULT 0, pinned_message_id TEXT, pinned_until INTEGER NOT NULL DEFAULT 0,
                description TEXT, username TEXT, invite_token TEXT,
                subscribers_count INTEGER NOT NULL DEFAULT 0, my_role TEXT,
                is_muted INTEGER NOT NULL DEFAULT 0)
            """,
            """
            CREATE TABLE chat_members (
                chat_id TEXT NOT NULL, user_id TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'member',
                PRIMARY KEY (chat_id, user_id))
            """,
            """
            CREATE TABLE messages (
                server_id TEXT PRIMARY KEY, client_message_id TEXT, chat_id TEXT NOT NULL,
                sender_id TEXT NOT NULL, type TEXT NOT NULL DEFAULT 'text',
                content TEXT NOT NULL DEFAULT '', file_key TEXT, local_path TEXT, thumbnail TEXT,
                protocol_version INTEGER NOT NULL DEFAULT 6, timestamp INTEGER NOT NULL,
                is_me INTEGER NOT NULL DEFAULT 0, delivery_status INTEGER NOT NULL DEFAULT 1,
                is_delivered INTEGER NOT NULL DEFAULT 0, is_read INTEGER NOT NULL DEFAULT 0,
                reply_to_id TEXT, is_forwarded INTEGER NOT NULL DEFAULT 0,
                is_edited INTEGER NOT NULL DEFAULT 0, edit_version INTEGER NOT NULL DEFAULT 0,
                ttl_seconds INTEGER NOT NULL DEFAULT 0, expires_at INTEGER NOT NULL DEFAULT 0,
                unverified_device INTEGER NOT NULL DEFAULT 0, reactions TEXT,
                requires_ack INTEGER NOT NULL DEFAULT 0, acks INTEGER NOT NULL DEFAULT 0,
                acked INTEGER NOT NULL DEFAULT 0, views INTEGER NOT NULL DEFAULT 0, reply_markup TEXT)
            """,
            "CREATE INDEX messages_chat_time ON messages(chat_id, timestamp)",
            "CREATE UNIQUE INDEX messages_client_id ON messages(client_message_id) WHERE client_message_id IS NOT NULL",
        ],
        // 2: device-only call history (Calls tab, Calls/CallLog.swift).
        [
            """
            CREATE TABLE call_log (
                id TEXT PRIMARY KEY, peer_id TEXT NOT NULL, chat_id TEXT NOT NULL,
                outgoing INTEGER NOT NULL DEFAULT 0, video INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'ok', duration INTEGER NOT NULL DEFAULT 0,
                timestamp INTEGER NOT NULL, seen INTEGER NOT NULL DEFAULT 1)
            """,
            "CREATE INDEX call_log_time ON call_log(timestamp)",
        ],
    ]

    static func migrate(_ db: Database) throws {
        let current = Int(try db.first("PRAGMA user_version") { $0.int(0) } ?? 0)
        guard current < steps.count else { return }
        for version in current..<steps.count {
            try db.transaction {
                for sql in steps[version] {
                    try db.execute(sql)
                }
                try db.execute("PRAGMA user_version = \(version + 1)")
            }
        }
    }

    /// Everything tied to the signed-in account. The device id (Keychain) survives - it names
    /// this install, not the account.
    static func wipeAccountData(_ db: Database) throws {
        try db.transaction {
            for table in ["kv", "sig_identity", "sig_prekey", "sig_signed_prekey", "sig_kyber_prekey",
                          "sig_kyber_base_key", "sig_session", "sig_sender_key", "sig_group_meta",
                          "users", "chats", "chat_members", "messages", "call_log"] {
                try db.execute("DELETE FROM \(table)")
            }
        }
    }
}
