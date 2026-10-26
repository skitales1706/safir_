import Foundation
import LibSignalClient

/// libsignal's stores backed by the local database - the same tables and rules as Android's
/// RatchetSignalProtocolStore / GroupSenderKeyStore, so both clients behave identically:
/// trust on first use, and a changed key or a never-seen device of a user we already know is
/// remembered as "change pending" until the user confirms it (senders refuse to encrypt to it).
/// The identity key pair itself lives in the Keychain (SignalService), not in the database.
final class SignalStore: IdentityKeyStore, PreKeyStore, SignedPreKeyStore, KyberPreKeyStore,
                         SessionStore, SenderKeyStore {
    private let db: Database
    private let identity: IdentityKeyPair
    private let registrationId: UInt32

    init(db: Database, identity: IdentityKeyPair, registrationId: UInt32) {
        self.db = db
        self.identity = identity
        self.registrationId = registrationId
    }

    // MARK: IdentityKeyStore

    func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair { identity }
    func localRegistrationId(context: StoreContext) throws -> UInt32 { registrationId }

    func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress, context: StoreContext) throws -> IdentityChange {
        let serialized = identity.serialize()
        return try db.transaction {
            let existing = try db.first(
                "SELECT identity_key, trusted_at, change_pending FROM sig_identity WHERE user_id = ? AND device_id = ?",
                [.text(address.name), .int(Int64(address.deviceId))]
            ) { row in (key: row.blob(0) ?? Data(), trustedAt: row.int(1), pending: row.int(2) != 0) }
            let changed = existing != nil && existing!.key != serialized
            // A device we've never seen for a user we already know is a possible "ghost device"
            // (the device list comes from the server) - treated exactly like a changed key.
            let otherDevices = try db.first("SELECT COUNT(*) FROM sig_identity WHERE user_id = ?", [.text(address.name)]) { $0.int(0) } ?? 0
            let newDeviceOfKnownUser = existing == nil && otherDevices > 0
            // An unacknowledged change must survive later saves of the same new key - libsignal
            // calls this on every PreKey decrypt.
            let pending = changed || newDeviceOfKnownUser || existing?.pending == true
            try db.execute(
                "INSERT OR REPLACE INTO sig_identity(user_id, device_id, identity_key, trusted_at, change_pending) VALUES(?, ?, ?, ?, ?)",
                [.text(address.name), .int(Int64(address.deviceId)), .blob(serialized),
                 .int(existing?.trustedAt ?? Clock.nowMs), .bool(pending)]
            )
            return changed ? .replacedExisting : .newOrUnchanged
        }
    }

    // Trust on first use - a rotated identity is flagged by saveIdentity and the SENDER refuses
    // to encrypt to it (SignalService), same as Android.
    func isTrustedIdentity(_ identity: IdentityKey, for address: ProtocolAddress, direction: Direction, context: StoreContext) throws -> Bool {
        true
    }

    func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
        let data = try db.first(
            "SELECT identity_key FROM sig_identity WHERE user_id = ? AND device_id = ?",
            [.text(address.name), .int(Int64(address.deviceId))]
        ) { $0.blob(0) }
        guard let bytes = data ?? nil else { return nil }
        return try IdentityKey(bytes: bytes)
    }

    // MARK: PreKeyStore

    func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
        guard let data = try record("sig_prekey", id) else {
            throw SignalError.invalidKeyIdentifier("no prekey \(id)")
        }
        return try PreKeyRecord(bytes: data)
    }

    func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
        try db.execute("INSERT OR REPLACE INTO sig_prekey(id, record) VALUES(?, ?)", [.int(Int64(id)), .blob(record.serialize())])
    }

    func removePreKey(id: UInt32, context: StoreContext) throws {
        try db.execute("DELETE FROM sig_prekey WHERE id = ?", [.int(Int64(id))])
    }

    // MARK: SignedPreKeyStore

    func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
        guard let data = try record("sig_signed_prekey", id) else {
            throw SignalError.invalidKeyIdentifier("no signed prekey \(id)")
        }
        return try SignedPreKeyRecord(bytes: data)
    }

    func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        try db.execute("INSERT OR REPLACE INTO sig_signed_prekey(id, record) VALUES(?, ?)", [.int(Int64(id)), .blob(record.serialize())])
    }

    // MARK: KyberPreKeyStore

    func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
        guard let data = try record("sig_kyber_prekey", id) else {
            throw SignalError.invalidKeyIdentifier("no kyber prekey \(id)")
        }
        return try KyberPreKeyRecord(bytes: data)
    }

    func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
        try db.execute("INSERT OR REPLACE INTO sig_kyber_prekey(id, record) VALUES(?, ?)", [.int(Int64(id)), .blob(record.serialize())])
    }

    // Our Kyber prekey is long-lived (last resort), so a replayed PreKeySignalMessage must be
    // rejected: the same (kyber prekey, signed prekey, base key) is accepted once.
    func markKyberPreKeyUsed(id: UInt32, signedPreKeyId: UInt32, baseKey: PublicKey, context: StoreContext) throws {
        try db.transaction {
            try db.execute(
                "INSERT OR IGNORE INTO sig_kyber_base_key(kyber_id, signed_id, base_key) VALUES(?, ?, ?)",
                [.int(Int64(id)), .int(Int64(signedPreKeyId)), .blob(baseKey.serialize())]
            )
            if db.changes == 0 {
                throw SignalError.invalidMessage("Kyber prekey \(id) reused with the same base key")
            }
        }
    }

    // MARK: SessionStore

    func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
        guard let data = try sessionData(address) else { return nil }
        return try SessionRecord(bytes: data)
    }

    func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
        try addresses.compactMap { address in
            try sessionData(address).map { try SessionRecord(bytes: $0) }
        }
    }

    func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
        try db.execute(
            "INSERT OR REPLACE INTO sig_session(user_id, device_id, record) VALUES(?, ?, ?)",
            [.text(address.name), .int(Int64(address.deviceId)), .blob(record.serialize())]
        )
    }

    // MARK: SenderKeyStore

    func storeSenderKey(from sender: ProtocolAddress, distributionId: UUID, record: SenderKeyRecord, context: StoreContext) throws {
        try db.execute(
            "INSERT OR REPLACE INTO sig_sender_key(user_id, device_id, distribution_id, record) VALUES(?, ?, ?, ?)",
            [.text(sender.name), .int(Int64(sender.deviceId)), .text(distributionId.uuidString.lowercased()), .blob(record.serialize())]
        )
    }

    func loadSenderKey(from sender: ProtocolAddress, distributionId: UUID, context: StoreContext) throws -> SenderKeyRecord? {
        let data = try db.first(
            "SELECT record FROM sig_sender_key WHERE user_id = ? AND device_id = ? AND distribution_id = ?",
            [.text(sender.name), .int(Int64(sender.deviceId)), .text(distributionId.uuidString.lowercased())]
        ) { $0.blob(0) }
        guard let bytes = data ?? nil else { return nil }
        return try SenderKeyRecord(bytes: bytes)
    }

    // MARK: Helpers used by SignalService

    func hasSession(_ address: ProtocolAddress) throws -> Bool {
        try sessionData(address) != nil
    }

    private func sessionData(_ address: ProtocolAddress) throws -> Data? {
        let data = try db.first(
            "SELECT record FROM sig_session WHERE user_id = ? AND device_id = ?",
            [.text(address.name), .int(Int64(address.deviceId))]
        ) { $0.blob(0) }
        return data ?? nil
    }

    private func record(_ table: String, _ id: UInt32) throws -> Data? {
        let data = try db.first("SELECT record FROM \(table) WHERE id = ?", [.int(Int64(id))]) { $0.blob(0) }
        return data ?? nil
    }
}

enum Clock {
    static var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
