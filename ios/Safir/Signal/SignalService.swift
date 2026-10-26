import CryptoKit
import Foundation
import LibSignalClient

struct SignalServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Signal Protocol for this install - a port of Android's RatchetManager + GroupRatchetManager,
/// so the wire format is identical across clients:
///
/// - 1:1: Double Ratchet (PQXDH) per (user, device). A send is encrypted once per device of the
///   partner AND once per OTHER device of my own account; the wire string is
///   "<CiphertextMessage type>:<base64>" and goes into `ratchet_contents[device]`.
/// - Groups: Sender Keys. Every member has their own chain; the distribution message travels to
///   each device over its 1:1 session (POST /chats/{id}/sender-key).
///
/// An actor: libsignal state must never be touched by two operations at once.
actor SignalService {
    static let shared = SignalService()

    static let protocolVersion = 6
    static let oneTimePreKeyTarget = 100
    static let oneTimePreKeyThreshold = 20
    private static let deviceListTTL: TimeInterval = 5 * 60
    private static let preKeyRotationMs: Int64 = 7 * 24 * 60 * 60 * 1000
    private static let oldPreKeyGraceMs: Int64 = 30 * 24 * 60 * 60 * 1000
    private static let groupSupportTTL: TimeInterval = 60 * 60

    private let db = Database.shared
    private let context = NullContext()
    private var deviceLists: [String: (devices: [RatchetIdentityInfo], at: Date)] = [:]
    private var groupSupport: [String: (supported: Bool, at: Date)] = [:]
    private var invalidBundles: Set<String> = []
    private var email = ""

    /// APIClient.shared, not Session - this actor also runs inside the Notification Service
    /// Extension, which has no app UI or Session.
    private var api: APIClient {
        get async { APIClient.shared }
    }

    // MARK: Identity

    /// The identity key pair is per account (keyed by email, like Android) and kept in the
    /// Keychain - never in the database, so a schema reset can't destroy it.
    func configure(email: String) {
        self.email = email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func identityKeyPair() throws -> IdentityKeyPair {
        guard !email.isEmpty else { throw SignalServiceError(message: "Signal not configured") }
        let key = "signal_identity_\(email)"
        if let stored = Keychain.get(key), let data = Data(base64Encoded: stored) {
            return try IdentityKeyPair(bytes: data)
        }
        let generated = IdentityKeyPair.generate()
        Keychain.set(generated.serialize().base64EncodedString(), for: key)
        return generated
    }

    private func registrationId() -> UInt32 {
        if let stored = db.int("signal_registration_id") { return UInt32(stored) }
        let id = UInt32.random(in: 1...16380)
        db.set(Int64(id), for: "signal_registration_id")
        return id
    }

    private func store() throws -> SignalStore {
        SignalStore(db: db, identity: try identityKeyPair(), registrationId: registrationId())
    }

    /// This install's small Signal device id (assigned by the server on the first bundle upload).
    func myDeviceId() -> Int? {
        db.int("signal_my_device_id").map { Int($0) }
    }

    func identityPublicKeyBase64() throws -> String {
        try identityKeyPair().publicKey.serialize().base64EncodedString()
    }

    private func address(_ userId: String, _ deviceId: Int) throws -> ProtocolAddress {
        try ProtocolAddress(name: userId.trimmingCharacters(in: .whitespaces).lowercased(), deviceId: UInt32(deviceId))
    }

    private func addressKey(_ userId: String, _ deviceId: Int) -> String {
        "\(userId.lowercased()).\(deviceId)"
    }

    // MARK: Bundle upload

    /// Generates (once) the signed Curve + Kyber prekeys and the one-time pool, rotating the
    /// signed ones weekly, and uploads the full bundle. Idempotent - safe on every launch.
    @discardableResult
    func ensureBundleUploaded(installId: String, oneTimeTarget: Int = SignalService.oneTimePreKeyTarget) async throws -> Int {
        let identity = try identityKeyPair()
        let regId = registrationId()
        let now = Clock.nowMs
        let mine = identity.publicKey

        func signedByMe(_ publicKey: Data, _ signature: Data) -> Bool {
            (try? mine.verifySignature(message: publicKey, signature: signature)) ?? false
        }

        // Signed Curve prekey - only one signed by THIS identity may be published.
        let signedRecords = try db.query("SELECT record FROM sig_signed_prekey") { try SignedPreKeyRecord(bytes: $0.blob(0) ?? Data()) }
        var signed = signedRecords
            .filter { (try? signedByMe($0.publicKey().serialize(), $0.signature)) ?? false }
            .max { $0.timestamp < $1.timestamp }
        if signed == nil || now - Int64(signed!.timestamp) >= Self.preKeyRotationMs {
            let id = nextId("signal_next_signed_prekey_id")
            let privateKey = PrivateKey.generate()
            let signature = identity.privateKey.generateSignature(message: privateKey.publicKey.serialize())
            let record = try SignedPreKeyRecord(id: id, timestamp: UInt64(now), privateKey: privateKey, signature: signature)
            try db.execute("INSERT OR REPLACE INTO sig_signed_prekey(id, record) VALUES(?, ?)", [.int(Int64(id)), .blob(record.serialize())])
            signed = record
        }
        let signedPreKey = signed!
        try pruneSuperseded(table: "sig_signed_prekey", stored: signedRecords.map { ($0.id, Int64($0.timestamp)) },
                            current: (signedPreKey.id, Int64(signedPreKey.timestamp)), now: now)

        // Signed Kyber prekey (PQXDH), same rotation.
        let kyberRecords = try db.query("SELECT record FROM sig_kyber_prekey") { try KyberPreKeyRecord(bytes: $0.blob(0) ?? Data()) }
        var kyber = kyberRecords
            .filter { (try? signedByMe($0.publicKey().serialize(), $0.signature)) ?? false }
            .max { $0.timestamp < $1.timestamp }
        if kyber == nil || now - Int64(kyber!.timestamp) >= Self.preKeyRotationMs {
            let id = nextId("signal_next_kyber_prekey_id")
            let keyPair = KEMKeyPair.generate()
            let signature = identity.privateKey.generateSignature(message: keyPair.publicKey.serialize())
            let record = try KyberPreKeyRecord(id: id, timestamp: UInt64(now), keyPair: keyPair, signature: signature)
            try db.execute("INSERT OR REPLACE INTO sig_kyber_prekey(id, record) VALUES(?, ?)", [.int(Int64(id)), .blob(record.serialize())])
            kyber = record
        }
        let kyberPreKey = kyber!
        let removedKyber = try pruneSuperseded(table: "sig_kyber_prekey", stored: kyberRecords.map { ($0.id, Int64($0.timestamp)) },
                                               current: (kyberPreKey.id, Int64(kyberPreKey.timestamp)), now: now)
        for id in removedKyber {
            try db.execute("DELETE FROM sig_kyber_base_key WHERE kyber_id = ?", [.int(Int64(id))])
        }

        // One-time pool: topped up to the target. The server REPLACES the whole pool on each
        // upload, so the full local pool is always sent.
        let existing = Int(try db.first("SELECT COUNT(*) FROM sig_prekey") { $0.int(0) } ?? 0)
        if existing < oneTimeTarget {
            var fresh: [PreKeyRecord] = []
            for _ in 0..<(oneTimeTarget - existing) {
                fresh.append(try PreKeyRecord(id: nextId("signal_next_prekey_id"), privateKey: PrivateKey.generate()))
            }
            try db.transaction {
                for record in fresh {
                    try db.execute("INSERT OR REPLACE INTO sig_prekey(id, record) VALUES(?, ?)",
                                   [.int(Int64(record.id)), .blob(record.serialize())])
                }
            }
        }
        let oneTime = try db.query("SELECT record FROM sig_prekey ORDER BY id") { row -> OneTimePreKeyDTO in
            let record = try PreKeyRecord(bytes: row.blob(0) ?? Data())
            return OneTimePreKeyDTO(keyId: Int(record.id), publicKey: try record.publicKey().serialize().base64EncodedString())
        }

        let request = UploadKeyBundleRequest(
            identityKey: identity.publicKey.serialize().base64EncodedString(),
            registrationId: Int(regId),
            signedPrekey: SignedPreKeyDTO(keyId: Int(signedPreKey.id),
                                          publicKey: try signedPreKey.publicKey().serialize().base64EncodedString(),
                                          signature: signedPreKey.signature.base64EncodedString()),
            kyberSignedPrekey: SignedPreKeyDTO(keyId: Int(kyberPreKey.id),
                                               publicKey: try kyberPreKey.publicKey().serialize().base64EncodedString(),
                                               signature: kyberPreKey.signature.base64EncodedString()),
            oneTimePrekeys: oneTime,
            deviceId: installId
        )
        let client = await api
        let response = try await client.post("keys/bundle", body: request, as: UploadKeyBundleResponse.self)
        db.set(Int64(response.ratchetDeviceId), for: "signal_my_device_id")
        AppLog.write("Signal bundle uploaded (device \(response.ratchetDeviceId), \(oneTime.count) one-time keys)")
        return response.ratchetDeviceId
    }

    /// GET /keys/prekey-count and re-upload when the pool ran low or the signed keys are due.
    func topUpIfNeeded(installId: String) async {
        do {
            let client = await api
            let count = try await client.get("keys/prekey-count", query: ["device_id": installId], as: PrekeyCountResponse.self).count
            if count >= Self.oneTimePreKeyThreshold, try !rotationDue() { return }
            try await ensureBundleUploaded(installId: installId)
        } catch {
            AppLog.write("Signal top-up failed: \(error.localizedDescription)")
        }
    }

    private func rotationDue() throws -> Bool {
        let now = Clock.nowMs
        let signed = try db.query("SELECT record FROM sig_signed_prekey") { Int64(try SignedPreKeyRecord(bytes: $0.blob(0) ?? Data()).timestamp) }.max()
        let kyber = try db.query("SELECT record FROM sig_kyber_prekey") { Int64(try KyberPreKeyRecord(bytes: $0.blob(0) ?? Data()).timestamp) }.max()
        guard let signed, let kyber else { return true }
        return now - signed >= Self.preKeyRotationMs || now - kyber >= Self.preKeyRotationMs
    }

    private func nextId(_ key: String) -> UInt32 {
        let id = db.int(key) ?? 1
        db.set(id + 1, for: key)
        return UInt32(id)
    }

    /// A non-current key is deleted once the key that replaced it has existed for longer than the
    /// grace period (in-flight PreKey messages may still need it). Returns the deleted ids.
    @discardableResult
    private func pruneSuperseded(table: String, stored: [(UInt32, Int64)], current: (UInt32, Int64), now: Int64) throws -> [UInt32] {
        let newestFirst = (stored.filter { $0.0 != current.0 } + [current]).sorted { $0.1 > $1.1 }
        guard newestFirst.count > 1 else { return [] }
        var removed: [UInt32] = []
        for i in 1..<newestFirst.count {
            let id = newestFirst[i].0
            if id != current.0 && now - newestFirst[i - 1].1 > Self.oldPreKeyGraceMs {
                try db.execute("DELETE FROM \(table) WHERE id = ?", [.int(Int64(id))])
                removed.append(id)
            }
        }
        return removed
    }

    // MARK: Device lists

    private func fetchDevicesNow(_ userId: String) async throws -> [RatchetIdentityInfo] {
        let key = userId.lowercased()
        let client = await api
        let list = try await client.get("keys/identities/\(key)", as: RatchetIdentityListResponse.self).identities
        deviceLists[key] = (devices: list, at: Date())
        return list
    }

    /// Throws on a network/server error - deliberately distinct from an empty list, so a failed
    /// lookup can never look like "this user has no Signal device".
    func deviceIds(for userId: String) async throws -> [Int] {
        let key = userId.lowercased()
        if let cached = deviceLists[key], Date().timeIntervalSince(cached.at) < Self.deviceListTTL {
            return cached.devices.map { $0.deviceId }
        }
        return try await fetchDevicesNow(key).map { $0.deviceId }
    }

    /// `user_keys_changed` over the WebSocket: the next send refetches this user's devices.
    func forgetDevices(of userId: String) {
        deviceLists[userId.lowercased()] = nil
        groupSupport = [:]
    }

    /// True once a session exists or the server lists at least one device. Refuses (throws) when
    /// the server suddenly reports none for a partner we already talked Signal with.
    func partnerSupportsSignal(_ partnerId: String) async throws -> Bool {
        let key = partnerId.lowercased()
        if try hasAnySession(with: key) { return true }
        let devices = try await deviceIds(for: key)
        if !devices.isEmpty { return true }
        let known = try db.first("SELECT COUNT(*) FROM sig_identity WHERE user_id = ?", [.text(key)]) { $0.int(0) } ?? 0
        if known > 0 {
            throw SignalServiceError(message: "Partner used Signal before but the server lists no devices")
        }
        return false
    }

    private func hasAnySession(with userId: String) throws -> Bool {
        (try db.first("SELECT COUNT(*) FROM sig_session WHERE user_id = ?", [.text(userId)]) { $0.int(0) } ?? 0) > 0
    }

    func isIdentityChangePending(_ userId: String) throws -> Bool {
        (try db.first("SELECT COUNT(*) FROM sig_identity WHERE user_id = ? AND change_pending = 1",
                      [.text(userId.lowercased())]) { $0.int(0) } ?? 0) > 0
    }

    func isDeviceUnconfirmed(_ userId: String, deviceId: Int) throws -> Bool {
        (try db.first("SELECT change_pending FROM sig_identity WHERE user_id = ? AND device_id = ?",
                      [.text(userId.lowercased()), .int(Int64(deviceId))]) { $0.int(0) } ?? 0) == 1
    }

    /// "I verified them" clears every device of that user at once (per-conversation check).
    func acknowledgeIdentityChange(_ userId: String) throws {
        try db.execute("UPDATE sig_identity SET change_pending = 0 WHERE user_id = ?", [.text(userId.lowercased())])
    }

    // MARK: 1:1 encrypt / decrypt

    /// Session with (user, device) if none yet (claims one of its one-time prekeys), then encrypts.
    /// Returns the wire string "<type>:<base64>", nil on failure.
    func encryptForDevice(_ userId: String, deviceId: Int, plaintext: String) async -> String? {
        do {
            let store = try store()
            let addr = try address(userId, deviceId)
            if try !store.hasSession(addr) {
                let client = await api
                let bundle = try await client.get("keys/bundle/\(userId.lowercased())",
                                                  query: ["device_id": String(deviceId)], as: KeyBundleResponse.self)
                do {
                    try processPreKeyBundle(try preKeyBundle(bundle), for: addr, sessionStore: store,
                                            identityStore: store, context: context)
                } catch let error as SignalError {
                    // That device published a bundle its own identity didn't sign - unreachable for
                    // everyone until it re-uploads. Remembered so a group send skips it.
                    switch error {
                    case .invalidSignature, .invalidKey:
                        invalidBundles.insert(addressKey(userId, deviceId))
                    default:
                        break
                    }
                    throw error
                }
                invalidBundles.remove(addressKey(userId, deviceId))
            }
            let message = try signalEncrypt(message: Data(plaintext.utf8), for: addr, sessionStore: store,
                                            identityStore: store, context: context)
            return "\(message.messageType.rawValue):\(message.serialize().base64EncodedString())"
        } catch {
            AppLog.write("Signal encrypt failed for a device: \(error)")
            return nil
        }
    }

    func hasInvalidBundle(_ userId: String, deviceId: Int) -> Bool {
        invalidBundles.contains(addressKey(userId, deviceId))
    }

    private func preKeyBundle(_ r: KeyBundleResponse) throws -> PreKeyBundle {
        func bytes(_ b64: String) throws -> Data {
            guard let d = Data(base64Encoded: b64) else { throw SignalServiceError(message: "bad base64 in bundle") }
            return d
        }
        let identity = try IdentityKey(bytes: try bytes(r.identityKey))
        let signedPublic = try PublicKey(try bytes(r.signedPrekey.publicKey))
        let signedSignature = try bytes(r.signedPrekey.signature)
        let kyberPublic = try KEMPublicKey(try bytes(r.kyberSignedPrekey.publicKey))
        let kyberSignature = try bytes(r.kyberSignedPrekey.signature)
        let deviceId = UInt32(r.deviceId ?? 1)
        if let oneTime = r.oneTimePrekey {
            return try PreKeyBundle(
                registrationId: UInt32(r.registrationId), deviceId: deviceId,
                prekeyId: UInt32(oneTime.keyId), prekey: try PublicKey(try bytes(oneTime.publicKey)),
                signedPrekeyId: UInt32(r.signedPrekey.keyId), signedPrekey: signedPublic,
                signedPrekeySignature: signedSignature, identity: identity,
                kyberPrekeyId: UInt32(r.kyberSignedPrekey.keyId), kyberPrekey: kyberPublic,
                kyberPrekeySignature: kyberSignature)
        }
        return try PreKeyBundle(
            registrationId: UInt32(r.registrationId), deviceId: deviceId,
            signedPrekeyId: UInt32(r.signedPrekey.keyId), signedPrekey: signedPublic,
            signedPrekeySignature: signedSignature, identity: identity,
            kyberPrekeyId: UInt32(r.kyberSignedPrekey.keyId), kyberPrekey: kyberPublic,
            kyberPrekeySignature: kyberSignature)
    }

    struct FanOut: Sendable {
        /// Device 1's ciphertext - the legacy single `content` field.
        let legacy: String?
        /// Signal device id -> wire ciphertext, for every device reached (`ratchet_contents`).
        let perDevice: [Int: String]
    }

    /// 1:1 send: once per device of the partner and once per OTHER device of my own account.
    func encryptForAllDevices(myUserId: String, partnerId: String, plaintext: String) async throws -> FanOut {
        let me = myUserId.lowercased()
        let partner = partnerId.lowercased()
        if try isIdentityChangePending(partner) {
            throw SignalServiceError(message: "Partner identity key changed and is not yet acknowledged")
        }
        let partnerDevices = try await deviceIds(for: partner)
        guard !partnerDevices.isEmpty else { throw SignalServiceError(message: "Partner has no Signal device") }
        let ownDevice = myDeviceId()
        let myDevices = try await deviceIds(for: me).filter { $0 != ownDevice }

        var perDevice: [Int: String] = [:]
        for device in partnerDevices {
            if let wire = await encryptForDevice(partner, deviceId: device, plaintext: plaintext) {
                perDevice[device] = wire
            }
        }
        for device in myDevices {
            guard let wire = await encryptForDevice(me, deviceId: device, plaintext: plaintext) else { continue }
            // Never fan out to an unconfirmed new device of MY OWN account (a device added by
            // someone holding my password) - it just can't read this message.
            if try isDeviceUnconfirmed(me, deviceId: device) { continue }
            perDevice[device] = wire
        }
        guard !perDevice.isEmpty else { throw SignalServiceError(message: "No device could be reached") }
        // Establishing a session may have just revealed a changed identity - never send to it.
        if try isIdentityChangePending(partner) {
            throw SignalServiceError(message: "Partner identity key changed and is not yet acknowledged")
        }
        return FanOut(legacy: perDevice[1], perDevice: perDevice)
    }

    /// Decrypts "<type>:<base64>" from (sender, device). Must run at most once per ciphertext -
    /// the message key is single-use (callers keep the plaintext).
    func decrypt(from senderId: String, deviceId: Int, wire: String) throws -> String {
        let store = try store()
        let addr = try address(senderId, deviceId)
        guard let sep = wire.firstIndex(of: ":"), let type = UInt8(wire[..<sep]),
              let bytes = Data(base64Encoded: String(wire[wire.index(after: sep)...])) else {
            throw SignalServiceError(message: "Malformed Signal wire content")
        }
        let plain: Data
        if type == CiphertextMessage.MessageType.preKey.rawValue {
            plain = try signalDecryptPreKey(message: try PreKeySignalMessage(bytes: bytes), from: addr,
                                            sessionStore: store, identityStore: store, preKeyStore: store,
                                            signedPreKeyStore: store, kyberPreKeyStore: store, context: context)
        } else {
            plain = try signalDecrypt(message: try SignalMessage(bytes: bytes), from: addr,
                                      sessionStore: store, identityStore: store, context: context)
        }
        guard let text = String(data: plain, encoding: .utf8) else {
            throw SignalServiceError(message: "Decrypted payload is not UTF-8")
        }
        return text
    }

    // MARK: Groups (Sender Keys)

    /// Every OTHER member must have a Signal device (a distribution travels over 1:1 sessions).
    func groupSupportsSignal(myUserId: String, memberIds: [String]) async throws -> Bool {
        let me = myUserId.lowercased()
        let others = Array(Set(memberIds.map { $0.lowercased() }.filter { $0 != me })).sorted()
        guard !others.isEmpty else { return false }
        let key = others.joined(separator: ",")
        if let cached = groupSupport[key], Date().timeIntervalSince(cached.at) < Self.groupSupportTTL {
            return cached.supported
        }
        var supported = true
        for member in others {
            let ok = try await partnerSupportsSignal(member)
            if !ok {
                supported = false
                break
            }
        }
        groupSupport[key] = (supported: supported, at: Date())
        return supported
    }

    /// Returns this device's distribution id for the chat, minting and distributing a fresh
    /// sender key when the group's key version moved on (membership change). Nil on failure.
    func ensureOwnSenderKeyCurrent(myUserId: String, installId: String, chatId: String,
                                   keyVersion: Int, memberIds: [String]) async -> UUID? {
        let chat = chatId.lowercased()
        let me = myUserId.lowercased()
        let meta = try? db.first("SELECT distribution_id, key_version FROM sig_group_meta WHERE chat_id = ?", [.text(chat)]) {
            (id: $0.text(0) ?? "", version: Int($0.int(1)))
        }
        if let meta, meta.version >= keyVersion {
            return UUID(uuidString: meta.id)
        }
        do {
            guard let myDevice = myDeviceId() else { throw SignalServiceError(message: "Signal bundle not registered yet") }
            let distributionId = UUID()
            let store = try store()
            let distribution = try SenderKeyDistributionMessage(from: try address(me, myDevice), distributionId: distributionId,
                                                                store: store, context: context)
            let distB64 = distribution.serialize().base64EncodedString()
            let others = Array(Set(memberIds.map { $0.lowercased() }.filter { $0 != me }))

            var items: [SenderKeyUploadItem] = []
            var expected = 0
            for target in others {
                let devices = try await deviceIds(for: target)
                if devices.isEmpty { expected += 1; continue }
                for device in devices {
                    if let wire = await encryptForDevice(target, deviceId: device, plaintext: distB64) {
                        expected += 1
                        items.append(SenderKeyUploadItem(targetId: target, ciphertext: wire, targetDeviceId: device))
                    } else if hasInvalidBundle(target, deviceId: device) {
                        AppLog.write("Skipping a member device with an invalid bundle")
                    } else {
                        expected += 1  // transient - abort, retried on the next send
                    }
                }
            }
            let memberItems = items.count
            // My other devices need my sender key too (best effort, unconfirmed ones skipped).
            for device in try await deviceIds(for: me) where device != myDevice {
                guard let wire = await encryptForDevice(me, deviceId: device, plaintext: distB64) else { continue }
                if try isDeviceUnconfirmed(me, deviceId: device) { continue }
                items.append(SenderKeyUploadItem(targetId: me, ciphertext: wire, targetDeviceId: device))
            }
            guard memberItems == expected else {
                AppLog.write("Sender key distribution incomplete - will retry")
                return nil
            }
            let client = await api
            try await client.send("POST", "chats/\(chat)/sender-key",
                                  body: UploadSenderKeyRequest(keyVersion: keyVersion, items: items, deviceId: installId))
            try db.execute("INSERT OR REPLACE INTO sig_group_meta(chat_id, distribution_id, key_version) VALUES(?, ?, ?)",
                           [.text(chat), .text(distributionId.uuidString.lowercased()), .int(Int64(keyVersion))])
            return distributionId
        } catch {
            AppLog.write("Sender key rotation failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pulls every distribution addressed to this device for the chat and processes it.
    func fetchDistributions(installId: String, chatId: String) async {
        do {
            let chat = chatId.lowercased()
            let client = await api
            let items = try await client.get("chats/\(chat)/sender-keys", query: ["device_id": installId],
                                             as: SenderKeysResponse.self).items
            let store = try store()
            for item in items {
                do {
                    let distB64 = try decrypt(from: item.senderId, deviceId: item.senderDeviceId ?? 1, wire: item.ciphertext)
                    guard let bytes = Data(base64Encoded: distB64) else { continue }
                    let message = try SenderKeyDistributionMessage(bytes: bytes)
                    try processSenderKeyDistributionMessage(message, from: try address(item.senderId, item.senderDeviceId ?? 1),
                                                            store: store, context: context)
                } catch {
                    AppLog.write("A sender key distribution could not be processed: \(error)")
                }
            }
        } catch {
            AppLog.write("Fetching sender keys failed: \(error.localizedDescription)")
        }
    }

    func encryptForGroup(myUserId: String, distributionId: UUID, plaintext: String) throws -> String {
        guard let myDevice = myDeviceId() else { throw SignalServiceError(message: "Signal bundle not registered yet") }
        let message = try groupEncrypt(Data(plaintext.utf8), from: try address(myUserId, myDevice),
                                       distributionId: distributionId, store: try store(), context: context)
        return message.serialize().base64EncodedString()
    }

    /// On the first failure (most likely that device's distribution isn't processed yet) pulls
    /// the distributions once and retries.
    func decryptGroup(installId: String, chatId: String, senderId: String, deviceId: Int, wire: String) async throws -> String {
        guard let bytes = Data(base64Encoded: wire) else { throw SignalServiceError(message: "Malformed group ciphertext") }
        do {
            return try groupDecryptOnce(bytes, senderId: senderId, deviceId: deviceId)
        } catch {
            await fetchDistributions(installId: installId, chatId: chatId)
            return try groupDecryptOnce(bytes, senderId: senderId, deviceId: deviceId)
        }
    }

    private func groupDecryptOnce(_ bytes: Data, senderId: String, deviceId: Int) throws -> String {
        let plain = try groupDecrypt(bytes, from: try address(senderId, deviceId), store: try store(), context: context)
        guard let text = String(data: plain, encoding: .utf8) else { throw SignalServiceError(message: "not UTF-8") }
        return text
    }

    // MARK: Safety number

    /// 60 digits over the Signal identity keys of both users' devices, "user:device:key" sorted
    /// and hashed with SHA-512 - identical to Android's RatchetManager.safetyNumber.
    func safetyNumber(myUserId: String, partnerId: String) async -> (digits: String, ownKeyMismatch: Bool)? {
        let me = myUserId.lowercased()
        let partner = partnerId.lowercased()
        guard let myKey = try? identityPublicKeyBase64() else { return nil }
        let myDevice = myDeviceId() ?? 1
        var entries: Set<String> = ["\(me):\(myDevice):\(myKey)"]
        var ownKeyMismatch = false
        if let mine = try? await fetchDevicesNow(me) {
            for d in mine {
                if d.deviceId == myDevice {
                    if d.identityKey != myKey { ownKeyMismatch = true }
                } else {
                    entries.insert("\(me):\(d.deviceId):\(d.identityKey)")
                }
            }
        }
        let local: [(Int, String)] = (try? db.query("SELECT device_id, identity_key FROM sig_identity WHERE user_id = ?", [.text(partner)]) {
            (Int($0.int(0)), ($0.blob(1) ?? Data()).base64EncodedString())
        }) ?? []
        for (device, key) in local { entries.insert("\(partner):\(device):\(key)") }
        let localDevices = Set(local.map { $0.0 })
        if let theirs = try? await fetchDevicesNow(partner) {
            for d in theirs where !localDevices.contains(d.deviceId) {
                entries.insert("\(partner):\(d.deviceId):\(d.identityKey)")
            }
        }
        guard entries.contains(where: { $0.hasPrefix("\(partner):") }) else { return nil }
        let joined = entries.sorted().joined(separator: "\n")
        let hash = Array(SHA512.hash(data: Data(joined.utf8)))
        var groups: [String] = []
        for i in 0..<12 {
            var value: UInt64 = 0
            for byte in hash[(i * 5)..<(i * 5 + 5)] { value = (value << 8) | UInt64(byte) }
            groups.append(String(format: "%05llu", value % 100000))
        }
        let lines = stride(from: 0, to: 12, by: 4).map { groups[$0..<($0 + 4)].joined(separator: " ") }
        return (lines.joined(separator: "\n"), ownKeyMismatch)
    }
}
