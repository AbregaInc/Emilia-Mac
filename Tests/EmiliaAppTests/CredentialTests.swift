import XCTest
import Security
@testable import Emilia

final class CredentialTests: XCTestCase {
    // Exercise OS status paths without creating real Keychain entries.
    func testNewKeyUsesDeviceOnlyUnlockedStorage() throws {
        var added = false
        try KeyStore.save(" test-key ", update: { _, _ in errSecItemNotFound }, add: { item, _ in
            let values = item as NSDictionary
            XCTAssertEqual(values[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            XCTAssertEqual(values[kSecValueData] as? Data, Data("test-key".utf8))
            added = true
            return errSecSuccess
        })
        XCTAssertTrue(added)
    }
    func testExistingKeyUpdatesWithoutDuplicateAndOSFailureIsSurfaced() throws {
        try KeyStore.save("replacement", update: { _, _ in errSecSuccess }, add: { _, _ in XCTFail("Must update existing item"); return errSecDuplicateItem })
        XCTAssertThrowsError(try KeyStore.save("key", update: { _, _ in errSecAuthFailed }, add: { _, _ in XCTFail("Do not retry authorization failure as insert"); return errSecSuccess }))
    }
}
