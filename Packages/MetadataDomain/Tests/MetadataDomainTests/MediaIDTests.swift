import XCTest
@testable import MetadataDomain

final class MediaIDTests: XCTestCase {

    func test_equality_sameProviderAndID_isEqual() {
        let a = MediaID(provider: .tmdb, id: 1668)
        let b = MediaID(provider: .tmdb, id: 1668)
        XCTAssertEqual(a, b)
    }

    func test_equality_differentID_notEqual() {
        let a = MediaID(provider: .tmdb, id: 1)
        let b = MediaID(provider: .tmdb, id: 2)
        XCTAssertNotEqual(a, b)
    }

    func test_hashing_equalIDs_haveEqualHashes() {
        let a = MediaID(provider: .tmdb, id: 42)
        let b = MediaID(provider: .tmdb, id: 42)
        var set: Set<MediaID> = []
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    func test_codable_roundTrip() throws {
        let original = MediaID(provider: .tmdb, id: 1668)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MediaID.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_codable_jsonShape() throws {
        let id = MediaID(provider: .tmdb, id: 1668)
        let data = try JSONEncoder().encode(id)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["provider"] as? String, "tmdb")
        XCTAssertEqual(json["id"] as? Int64, 1668)
    }
}
