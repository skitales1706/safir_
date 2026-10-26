import LibSignalClient
import XCTest
@testable import Safir

/// Signal through OUR stores (SignalStore on the SQLite Database) with the real libsignal - the
/// part every message depends on. Two independent "devices", each with its own database file.
final class SignalProtocolTests: XCTestCase {
    private struct Device {
        let db: Database
        let identity: IdentityKeyPair
        let store: SignalStore
        let address: ProtocolAddress
    }

    private let context = NullContext()

    private func makeDevice(_ user: String, deviceId: UInt32) throws -> Device {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        let db = try Database(url: url)
        let identity = IdentityKeyPair.generate()
        let store = SignalStore(db: db, identity: identity, registrationId: UInt32.random(in: 1...16380))
        return Device(db: db, identity: identity, store: store, address: try ProtocolAddress(name: user, deviceId: deviceId))
    }

    /// Bob publishes signed + Kyber + one-time prekeys exactly like SignalService.ensureBundleUploaded.
    private func publishBundle(_ bob: Device) throws -> PreKeyBundle {
        let signedPrivate = PrivateKey.generate()
        let signed = try SignedPreKeyRecord(id: 1, timestamp: UInt64(Clock.nowMs), privateKey: signedPrivate,
                                            signature: bob.identity.privateKey.generateSignature(message: signedPrivate.publicKey.serialize()))
        try bob.store.storeSignedPreKey(signed, id: 1, context: context)
        let kem = KEMKeyPair.generate()
        let kyber = try KyberPreKeyRecord(id: 1, timestamp: UInt64(Clock.nowMs), keyPair: kem,
                                          signature: bob.identity.privateKey.generateSignature(message: kem.publicKey.serialize()))
        try bob.store.storeKyberPreKey(kyber, id: 1, context: context)
        let oneTime = try PreKeyRecord(id: 7, privateKey: PrivateKey.generate())
        try bob.store.storePreKey(oneTime, id: 7, context: context)
        return try PreKeyBundle(
            registrationId: try bob.store.localRegistrationId(context: context), deviceId: bob.address.deviceId,
            prekeyId: 7, prekey: try oneTime.publicKey(),
            signedPrekeyId: 1, signedPrekey: try signed.publicKey(), signedPrekeySignature: signed.signature,
            identity: bob.identity.identityKey,
            kyberPrekeyId: 1, kyberPrekey: try kyber.publicKey(), kyberPrekeySignature: kyber.signature)
    }

    /// Wire format used by every client: "<type>:<base64>".
    private func wire(_ m: CiphertextMessage) -> String {
        "\(m.messageType.rawValue):\(m.serialize().base64EncodedString())"
    }

    private func decrypt(_ wire: String, at device: Device, from sender: ProtocolAddress) throws -> String {
        let sep = wire.firstIndex(of: ":")!
        let type = UInt8(wire[..<sep])!
        let bytes = Data(base64Encoded: String(wire[wire.index(after: sep)...]))!
        let plain: Data
        if type == CiphertextMessage.MessageType.preKey.rawValue {
            plain = try signalDecryptPreKey(message: try PreKeySignalMessage(bytes: bytes), from: sender,
                                            sessionStore: device.store, identityStore: device.store,
                                            preKeyStore: device.store, signedPreKeyStore: device.store,
                                            kyberPreKeyStore: device.store, context: context)
        } else {
            plain = try signalDecrypt(message: try SignalMessage(bytes: bytes), from: sender,
                                      sessionStore: device.store, identityStore: device.store, context: context)
        }
        return String(data: plain, encoding: .utf8)!
    }

    func testOneToOneConversationBothDirections() throws {
        let alice = try makeDevice("alice", deviceId: 1)
        let bob = try makeDevice("bob", deviceId: 2)
        try processPreKeyBundle(try publishBundle(bob), for: bob.address, sessionStore: alice.store,
                                identityStore: alice.store, context: context)
        XCTAssertTrue(try alice.store.hasSession(bob.address))

        let first = try signalEncrypt(message: Data("Салом, Bob!".utf8), for: bob.address, sessionStore: alice.store,
                                      identityStore: alice.store, context: context)
        XCTAssertEqual(first.messageType, .preKey)
        XCTAssertEqual(try decrypt(wire(first), at: bob, from: alice.address), "Салом, Bob!")

        let reply = try signalEncrypt(message: Data("Hi Alice".utf8), for: alice.address, sessionStore: bob.store,
                                      identityStore: bob.store, context: context)
        XCTAssertEqual(try decrypt(wire(reply), at: alice, from: bob.address), "Hi Alice")

        // Once Alice has heard back, her messages are plain ratchet messages.
        let third = try signalEncrypt(message: Data("3".utf8), for: bob.address, sessionStore: alice.store,
                                      identityStore: alice.store, context: context)
        XCTAssertEqual(third.messageType, .whisper)
        XCTAssertEqual(try decrypt(wire(third), at: bob, from: alice.address), "3")
    }

    func testMessageKeyIsSingleUse() throws {
        let alice = try makeDevice("alice", deviceId: 1)
        let bob = try makeDevice("bob", deviceId: 2)
        try processPreKeyBundle(try publishBundle(bob), for: bob.address, sessionStore: alice.store,
                                identityStore: alice.store, context: context)
        let m = wire(try signalEncrypt(message: Data("once".utf8), for: bob.address, sessionStore: alice.store,
                                       identityStore: alice.store, context: context))
        XCTAssertEqual(try decrypt(m, at: bob, from: alice.address), "once")
        XCTAssertThrowsError(try decrypt(m, at: bob, from: alice.address))
    }

    func testSessionsSurviveReopeningTheDatabase() throws {
        let alice = try makeDevice("alice", deviceId: 1)
        let bob = try makeDevice("bob", deviceId: 2)
        try processPreKeyBundle(try publishBundle(bob), for: bob.address, sessionStore: alice.store,
                                identityStore: alice.store, context: context)
        let m = wire(try signalEncrypt(message: Data("persist".utf8), for: bob.address, sessionStore: alice.store,
                                       identityStore: alice.store, context: context))
        // A fresh store over the same database = the app restarted.
        let reopened = Device(db: bob.db, identity: bob.identity,
                              store: SignalStore(db: bob.db, identity: bob.identity,
                                                 registrationId: try bob.store.localRegistrationId(context: context)),
                              address: bob.address)
        XCTAssertEqual(try decrypt(m, at: reopened, from: alice.address), "persist")
    }

    func testNewDeviceOfKnownUserIsFlagged() throws {
        let alice = try makeDevice("alice", deviceId: 1)
        let carol1 = IdentityKeyPair.generate().identityKey
        let carol2 = IdentityKeyPair.generate().identityKey
        let first = try ProtocolAddress(name: "carol", deviceId: 1)
        let second = try ProtocolAddress(name: "carol", deviceId: 2)
        XCTAssertEqual(try alice.store.saveIdentity(carol1, for: first, context: context), .newOrUnchanged)
        // A device nobody confirmed appearing for someone we already know: "ghost device" candidate.
        _ = try alice.store.saveIdentity(carol2, for: second, context: context)
        let pending = try alice.db.first("SELECT change_pending FROM sig_identity WHERE user_id = 'carol' AND device_id = 2") { $0.int(0) }
        XCTAssertEqual(pending, 1)
        // A changed key on a known device is reported and flagged too.
        XCTAssertEqual(try alice.store.saveIdentity(carol2, for: first, context: context), .replacedExisting)
    }

    func testGroupSenderKeys() throws {
        let alice = try makeDevice("alice", deviceId: 1)
        let bob = try makeDevice("bob", deviceId: 2)
        let distributionId = UUID()
        let distribution = try SenderKeyDistributionMessage(from: alice.address, distributionId: distributionId,
                                                            store: alice.store, context: context)
        // Travels base64 inside a 1:1 Signal message, then processed by the member.
        let received = try SenderKeyDistributionMessage(bytes: Data(base64Encoded: distribution.serialize().base64EncodedString())!)
        try processSenderKeyDistributionMessage(received, from: alice.address, store: bob.store, context: context)

        let sealed = try groupEncrypt(Data("Всем привет".utf8), from: alice.address, distributionId: distributionId,
                                      store: alice.store, context: context)
        let wire = sealed.serialize().base64EncodedString()
        let plain = try groupDecrypt(Data(base64Encoded: wire)!, from: alice.address, store: bob.store, context: context)
        XCTAssertEqual(String(data: plain, encoding: .utf8), "Всем привет")
    }

    func testKyberReplayIsRejected() throws {
        let bob = try makeDevice("bob", deviceId: 2)
        let base = PrivateKey.generate().publicKey
        XCTAssertNoThrow(try bob.store.markKyberPreKeyUsed(id: 1, signedPreKeyId: 1, baseKey: base, context: context))
        XCTAssertThrowsError(try bob.store.markKyberPreKeyUsed(id: 1, signedPreKeyId: 1, baseKey: base, context: context))
    }
}

/// Byte compatibility with Android (SecurityUtils / MediaThumbnails): vectors made with Python's
/// AESGCM in the same layout - IV(12) || ciphertext || tag.
final class MediaCryptoTests: XCTestCase {
    private let keyB64 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="

    func testDecryptsAndroidFile() throws {
        let sealed = Data(base64Encoded: "ZGVmZ2hpamtsbW5vmLoO1qlShiDu3nPIiQQMlDDjJju5X/F+WYbMJMnvfbtBUcwfyVU=")!
        let plain = try MediaCrypto.decrypt(sealed, key: XCTUnwrap(MediaCrypto.key(fromBase64: keyB64)))
        XCTAssertEqual(String(data: plain, encoding: .utf8), "Салом, Safir! 123")
    }

    func testDecryptsAndroidThumbnailWithRoleBinding() {
        let thumb = MediaCrypto.openThumbnail("ZGVmZ2hpamtsbW5vt8OqDgyENOv5qxwZx34rNsPzK9Xemes=", keyBase64: keyB64)
        XCTAssertEqual(thumb, Data([0xFF, 0xD8]) + Data("thumb".utf8))
        // The file ciphertext must not open as a thumbnail (different AAD).
        XCTAssertNil(MediaCrypto.openThumbnail("ZGVmZ2hpamtsbW5vmLoO1qlShiDu3nPIiQQMlDDjJju5X/F+WYbMJMnvfbtBUcwfyVU=", keyBase64: keyB64))
    }

    func testRoundTripAndTamperDetection() throws {
        let key = MediaCrypto.newKey()
        var sealed = try MediaCrypto.encrypt(Data("photo".utf8), key: key)
        XCTAssertEqual(try MediaCrypto.decrypt(sealed, key: key), Data("photo".utf8))
        sealed[sealed.count - 1] ^= 0x01
        XCTAssertThrowsError(try MediaCrypto.decrypt(sealed, key: key))
        XCTAssertNotNil(MediaCrypto.key(fromBase64: MediaCrypto.keyBase64(key)))
    }

    func testArchiveKeyParsesSPKIPem() {
        let pem = """
        -----BEGIN PUBLIC KEY-----
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA9F2twEUSureMBbzIn0Fp
        ZoiXWYTXTdDKThJJNALkOj44CUsdymQc4h18pqEQIlL88NYb6gcO7n7Uq7JH2XZB
        5zl7utoZTVBcpPPb70YQ00uRThwPUbDTK7cHSCi+XwqfqpPQpRM+CdRMS9JjDA//
        gBHMP/LwKMCa+zbhBF6Unu99W/jt87uAdUlvKLys7Ge/BeCgdFfKs86Jbv35lXAF
        EBbE+P1BVeRKZAXJJIuOpksDXMUmVnEZqRq6Xme6Ico0omHhoSIRm0gRBgDA6QES
        NhLRpNzgFWwMj+r577T3RWrhurYcsIVfhav4gTj4VtbT/P3nj5+yhvDp8BP8Kc4m
        JQIDAQAB
        -----END PUBLIC KEY-----
        """
        let key = ArchiveSealer.rsaPublicKey(pem: pem)
        XCTAssertNotNil(key)
        var error: Unmanaged<CFError>?
        let wrapped = key.flatMap { SecKeyCreateEncryptedData($0, .rsaEncryptionOAEPSHA256, Data(count: 32) as CFData, &error) }
        XCTAssertEqual((wrapped as Data?)?.count, 256)
    }
}
