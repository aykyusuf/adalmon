import Security
import XCTest
@testable import Adalmon

final class HelperCommandValidationTests: XCTestCase {
    // MARK: Aralık denetimi

    func testChargeLimitAcceptsValidValues() throws {
        for limit in stride(from: 50, through: 100, by: 5) {
            let floor = max(limit - 5, 20)
            let command = try HelperCommand.chargeLimit(enabled: true, limit: limit, sailingFloor: floor, topUp: false).get()
            XCTAssertEqual(command, .setChargeLimit(enabled: true, limit: limit, sailingFloor: floor, topUp: false))
        }
    }

    func testChargeLimitRejectsOutOfRangeAndOffStep() {
        for limit in [-5, 0, 49, 51, 83, 101, 105, Int.max, Int.min] {
            XCTAssertEqual(rejection(HelperCommand.chargeLimit(enabled: true, limit: limit, sailingFloor: 40, topUp: false)), .outOfRange, "limit \(limit)")
        }
    }

    func testSailingFloorMustBeBelowLimitAboveWatchdogAndWithinGap() {
        XCTAssertEqual(rejection(HelperCommand.chargeLimit(enabled: true, limit: 80, sailingFloor: 80, topUp: false)), .outOfRange)
        XCTAssertEqual(rejection(HelperCommand.chargeLimit(enabled: true, limit: 80, sailingFloor: 90, topUp: false)), .outOfRange)
        XCTAssertEqual(rejection(HelperCommand.chargeLimit(enabled: true, limit: 80, sailingFloor: 19, topUp: false)), .outOfRange)
        XCTAssertEqual(rejection(HelperCommand.chargeLimit(enabled: true, limit: 90, sailingFloor: 55, topUp: false)), .outOfRange, "aralık > 30")
        XCTAssertNil(rejection(HelperCommand.chargeLimit(enabled: true, limit: 50, sailingFloor: 20, topUp: false)))
        XCTAssertNil(rejection(HelperCommand.chargeLimit(enabled: true, limit: 100, sailingFloor: 0, topUp: false)), "100: seyir alanı kullanılmaz")
    }

    func testDisabledRequestsAreStillRangeChecked() {
        XCTAssertEqual(rejection(HelperCommand.chargeLimit(enabled: false, limit: 7, sailingFloor: 1, topUp: false)), .outOfRange)
    }

    func testManualInhibitTTLBounds() {
        XCTAssertEqual(rejection(HelperCommand.chargingInhibited(true, ttlSeconds: 59)), .outOfRange)
        XCTAssertEqual(rejection(HelperCommand.chargingInhibited(true, ttlSeconds: 3601)), .outOfRange)
        XCTAssertEqual(rejection(HelperCommand.chargingInhibited(true, ttlSeconds: -1)), .outOfRange)
        XCTAssertNil(rejection(HelperCommand.chargingInhibited(true, ttlSeconds: 60)))
        XCTAssertNil(rejection(HelperCommand.chargingInhibited(false, ttlSeconds: 3600)))
    }

    func testLEDRawValuesAreWhitelisted() {
        for raw in [-1, 4, 5, 255, Int.max] { XCTAssertEqual(rejection(HelperCommand.magSafeLED(rawValue: raw)), .outOfRange) }
        for mode in MagSafeLEDMode.allCases {
            XCTAssertEqual(try HelperCommand.magSafeLED(rawValue: mode.rawValue).get(), .setMagSafeLED(mode))
        }
    }

    private func rejection(_ result: Result<HelperCommand, HelperErrorCode>) -> HelperErrorCode? {
        if case let .failure(e) = result { return e }
        return nil
    }

    // MARK: SMC yazma izin listesi

    func testAllowlistPermitsOnlyKnownValues() {
        XCTAssertTrue(SMCWriteAllowlist.permits(SMCWrite(key: .chte, bytes: [1, 0, 0, 0])))
        XCTAssertTrue(SMCWriteAllowlist.permits(SMCWrite(key: .chte, bytes: [0, 0, 0, 0])))
        XCTAssertFalse(SMCWriteAllowlist.permits(SMCWrite(key: .chte, bytes: [2, 0, 0, 0])))
        XCTAssertFalse(SMCWriteAllowlist.permits(SMCWrite(key: .chte, bytes: [1])))
        XCTAssertFalse(SMCWriteAllowlist.permits(SMCWrite(key: .chte, bytes: [0xFF, 0xFF, 0xFF, 0xFF])))
        XCTAssertTrue(SMCWriteAllowlist.permits(SMCWrite(key: .ch0b, bytes: [2])))
        XCTAssertTrue(SMCWriteAllowlist.permits(SMCWrite(key: .ch0c, bytes: [0])))
        XCTAssertFalse(SMCWriteAllowlist.permits(SMCWrite(key: .ch0b, bytes: [1])))
        XCTAssertFalse(SMCWriteAllowlist.permits(SMCWrite(key: .ch0c, bytes: [2, 0])))
        XCTAssertFalse(SMCWriteAllowlist.permits(SMCWrite(key: .aclc, bytes: [2])))
        XCTAssertFalse(SMCWriteAllowlist.permits(SMCWrite(key: .aclc, bytes: [0, 0])))
        XCTAssertFalse(SMCWriteAllowlist.permits(SMCWrite(key: .aclc, bytes: [255])))
    }

    func testEveryGeneratedWriteIsPermitted() {
        for method in [ChargeInhibitMethod.chte, .ch0bc] {
            for inhibited in [true, false] {
                for w in SMCWriteAllowlist.inhibitWrites(method: method, inhibited: inhibited) { XCTAssertTrue(SMCWriteAllowlist.permits(w)) }
            }
        }
        for mode in MagSafeLEDMode.allCases { XCTAssertTrue(SMCWriteAllowlist.permits(SMCWriteAllowlist.ledWrite(mode))) }
        XCTAssertEqual(SMCWriteAllowlist.ledWrite(.auto).bytes, [0], "otomatik = sistem denetimi")
    }

    func testAllowedSMCKeysAreExactlyTheKnownList() {
        XCTAssertEqual(Set(SMCKey.allCases.map(\.rawValue)), ["CHTE", "CH0B", "CH0C", "ACLC"])
    }

    // MARK: Yöntem tespiti

    func testMethodDetectionNeedsExpectedKeySizes() {
        XCTAssertNil(ChargeInhibitMethod.detect(sizes: [:]))
        XCTAssertNil(ChargeInhibitMethod.detect(sizes: [.aclc: 1]), "bu Mac: yalnız ACLC var")
        XCTAssertEqual(ChargeInhibitMethod.detect(sizes: [.chte: 4]), .chte)
        XCTAssertNil(ChargeInhibitMethod.detect(sizes: [.chte: 1]))
        XCTAssertEqual(ChargeInhibitMethod.detect(sizes: [.ch0b: 1, .ch0c: 1]), .ch0bc)
        XCTAssertNil(ChargeInhibitMethod.detect(sizes: [.ch0b: 1]))
        XCTAssertNil(ChargeInhibitMethod.detect(sizes: [.ch0b: 2, .ch0c: 1]))
    }

    // MARK: İstemci gereksinimi (kod imzası)

    func testClientRequirementPinsTeamIdentifierAndAppleAnchor() {
        let r = HelperConstants.clientRequirement
        XCTAssertTrue(r.contains("anchor apple generic"))
        XCTAssertTrue(r.contains("identifier \"com.example.adalmon\""))
        XCTAssertTrue(r.contains("certificate leaf[subject.OU] = \"YOUR_TEAM_ID\""))
        XCTAssertEqual(HelperConstants.teamID, "YOUR_TEAM_ID")
    }

    func testRequirementStringsParse() {
        for text in [HelperConstants.clientRequirement, HelperConstants.helperRequirement] {
            var requirement: SecRequirement?
            XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess, text)
            XCTAssertNotNil(requirement)
        }
        XCTAssertNotEqual(HelperConstants.clientRequirement, HelperConstants.helperRequirement)
    }

    func testRequirementSeparatesAppFromHelper() throws {
        var code: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &code), errSecSuccess)
        let hostCode = try XCTUnwrap(code)
        var staticCode: SecStaticCode?
        XCTAssertEqual(SecCodeCopyStaticCode(hostCode, [], &staticCode), errSecSuccess)
        var info: CFDictionary?
        SecCodeCopySigningInformation(try XCTUnwrap(staticCode), SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
        try XCTSkipUnless(team == HelperConstants.teamID, "test sunucusu takım kimliğiyle imzalı değil")

        func satisfies(_ text: String) -> Bool {
            var req: SecRequirement?
            guard SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess, let req else { return false }
            return SecCodeCheckValidity(hostCode, [], req) == errSecSuccess
        }
        XCTAssertTrue(satisfies(HelperConstants.clientRequirement), "uygulama kendi kuralını sağlamalı")
        XCTAssertFalse(satisfies(HelperConstants.helperRequirement), "uygulama yardımcı olarak kabul edilmemeli")
        XCTAssertFalse(satisfies(HelperConstants.requirement(identifier: "com.example.evil")))
    }

    // MARK: Paket düzeni (SMAppService.daemon)

    func testLaunchDaemonPlistMatchesConstantsAndBundleLayout() throws {
        let app = Bundle.main.bundleURL
        let plistURL = app.appending(path: "Contents/Library/LaunchDaemons/\(HelperConstants.launchDaemonPlistName)")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, HelperConstants.machServiceName)
        let program = try XCTUnwrap(plist["BundleProgram"] as? String)
        XCTAssertEqual(program, "Contents/MacOS/\(HelperConstants.helperExecutableName)")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: app.appending(path: program).path))
        let mach = try XCTUnwrap(plist["MachServices"] as? [String: Any])
        XCTAssertEqual(mach[HelperConstants.machServiceName] as? Bool, true)
        XCTAssertEqual(plist["AssociatedBundleIdentifiers"] as? [String], [HelperConstants.appIdentifier])
        XCTAssertEqual(HelperConstants.launchDaemonPlistName, HelperConstants.machServiceName + ".plist")
    }

    // MARK: Kodlama

    func testReplyRoundTrip() throws {
        var status = HelperStatus()
        status.inhibitMethod = .chte
        status.config = ChargeConfig(enabled: true, limit: 80, sailingFloor: 75, topUpStartedAt: Date(timeIntervalSince1970: 1_800_000_000))
        status.lastError = .smcFailure
        let reply = HelperReply.failure(.smcFailure, status)
        let decoded = try XCTUnwrap(HelperCoding.decode(HelperReply.self, from: HelperCoding.encode(reply)))
        XCTAssertEqual(decoded, reply)
        XCTAssertNil(HelperCoding.decode(HelperReply.self, from: Data("junk".utf8)))
    }
}
