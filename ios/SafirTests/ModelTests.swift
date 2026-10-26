import XCTest
@testable import Safir

/// Parsing of real backend payloads (snake_case, as schemas.py sends them) and the local store.
final class ModelTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient(baseURL: APIClient.defaultServer).decode(type, from: Data(json.utf8))
    }

    func testMessageFromServer() throws {
        let m = try decode(APIMessage.self, """
        {"id": "m1", "chat_id": "C1", "sender_id": "U1", "content": "2:QUJD", "encrypted_key": null,
         "ratchet_contents": {"1": "3:AAA", "2": "2:BBB"}, "sender_device_id": 2, "protocol_version": 6,
         "protocol_version_sender": 6, "type": "text", "is_delivered": true, "is_read": false,
         "created_at": "2026-10-22T10:15:30.123456", "edit_version": 1, "expires_at": null,
         "client_message_id": "abc", "thumbnail": null, "reply_markup": {"inline_keyboard": []}}
        """)
        XCTAssertEqual(m.ratchetContents?["2"], "2:BBB")
        XCTAssertEqual(m.senderDeviceId, 2)
        XCTAssertEqual(m.editVersion, 1)
        XCTAssertEqual(Dates.millis(m.createdAt), 1_792_664_130_000)
    }

    func testTokenAndSync() throws {
        let t = try decode(TokenResponse.self, """
        {"access_token": "tok", "token_type": "bearer", "mfa_required": true,
         "user": {"id": "U1", "username": "ali", "email": "", "full_name": "Ali"}}
        """)
        XCTAssertEqual(t.mfaRequired, true)
        XCTAssertEqual(t.user.fullName, "Ali")
        let s = try decode(SyncResponse.self, """
        {"messages": [], "chats": {"0b4f-uuid": {"is_group": false, "member_ids": ["a", "b"]}},
         "server_time": "2026-10-22T10:00:00"}
        """)
        XCTAssertEqual(s.chats["0b4f-uuid"]?.memberIds, ["a", "b"])
    }

    func testRequestIsSnakeCase() throws {
        let body = MessageRequest(content: "x", type: "text", clientMessageId: "c", encryptedKey: nil,
                                  ratchetContents: ["1": "w"], senderDeviceId: 3, protocolVersion: 6,
                                  protocolVersionSender: 6, groupKeyVersion: nil, replyToId: nil,
                                  isForwarded: false, thumbnail: nil, requiresAck: nil, archive: nil)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(body)) as? [String: Any])
        XCTAssertEqual(json["client_message_id"] as? String, "c")
        XCTAssertEqual(json["sender_device_id"] as? Int, 3)
        XCTAssertEqual((json["ratchet_contents"] as? [String: String])?["1"], "w")
        XCTAssertNil(json["encrypted_key"])
    }

    func testDatesAndChatIds() {
        XCTAssertEqual(Dates.millis("2026-10-22T10:15:30Z"), Dates.millis("2026-10-22T10:15:30.5+00:00"))
        XCTAssertEqual(Dates.millis(nil), 0)
        XCTAssertEqual(ChatIds.direct("B", "a"), "a_b")
        XCTAssertEqual(ChatIds.apiTarget("a_b", myUserId: "a"), "b")
        XCTAssertEqual(ChatIds.apiTarget("group-1", myUserId: "a"), "group-1")
    }

    func testDLPPolicyDefaultsAndLimits() throws {
        let p = try decode(DLPPolicy.self, """
        {"block_copy": true, "allowed_media": ["image"], "max_file_mb": 1, "wipe": false}
        """)
        XCTAssertTrue(p.blockCopy)
        XCTAssertFalse(p.watermark)
        XCTAssertNil(p.refusal(type: "image", bytes: 1000))
        XCTAssertNotNil(p.refusal(type: "video", bytes: 10))
        XCTAssertNotNil(p.refusal(type: "image", bytes: 2 * 1024 * 1024))
    }

    func testDatabaseSchemaAndTransactions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        let db = try Database(url: url)
        let version = try db.first("PRAGMA user_version") { $0.int(0) }
        XCTAssertEqual(version, 2)
        db.set("v", for: "k")
        XCTAssertEqual(db.string("k"), "v")
        XCTAssertThrowsError(try db.transaction {
            try db.execute("INSERT INTO kv(key, value) VALUES('rolled', 'back')")
            throw DatabaseError(message: "abort")
        })
        XCTAssertNil(db.string("rolled"))
        // Reopening runs no migration twice.
        XCTAssertNoThrow(try Database(url: url))
    }
}
