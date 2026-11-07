import XCTest
@testable import Adalmon

final class BackgroundItemParserTests: XCTestCase {
    private let dump = """
    ========================
     Records for UID -2 : FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE
    ========================

     Items:

     #1:
                     UUID: 11111111-0000-0000-0000-000000000001
                     Name: Global Thing
                     Type: login item (0x4)
              Disposition: [enabled, allowed, notified] (0xb)
               Identifier: 4.com.global.thing

    ========================
     Records for UID 501 : BF7C4A3C-F23F-4197-9387-AC60141B731F
    ========================

     Items:

     #1:
                     UUID: 04ECB920-0000-0000-0000-000000000001
                     Name: (null)
           Developer Name: (null)
                     Type: developer (0x20)
              Disposition: [disabled, allowed, not notified] (0x2)
               Identifier: Unknown Developer
      Embedded Item Identifiers:
        #1: 8.homebrew.mxcl.postgresql@14

     #2:
                     UUID: 829AA94A-0000-0000-0000-000000000002
                     Name: Docker
           Developer Name: Docker Inc
                     Type: app (0x2)
              Disposition: [enabled, allowed, notified] (0xb)
               Identifier: 2.com.docker.docker

     #3:
                     UUID: 829AA94A-0000-0000-0000-000000000003
                     Name: DockerHelper
           Developer Name: Docker Inc
                     Type: login item (0x4)
                    Flags: [  ] (0)
              Disposition: [enabled, allowed, notified] (0xb)
               Identifier: 4.com.docker.helper
                      URL: Contents/Library/LoginItems/DockerHelper.app
        Bundle Identifier: com.docker.helper
        Parent Identifier: 2.com.docker.docker

     #4:
                     UUID: 24A00000-0000-0000-0000-000000000004
                     Name: 24 Hour Wallpaper Helper
           Developer Name: Jetson Creative LLC
                     Type: login item (0x4)
              Disposition: [disabled, allowed, notified] (0xa)
               Identifier: 4.com.jetson.helper
        Bundle Identifier: com.jetson.helper

     #5:
                     UUID: 19A8830A-0000-0000-0000-000000000005
                     Name: deno
                     Type: legacy agent (0x10008)
              Disposition: [enabled, allowed, notified] (0xb)
               Identifier: 8.music.rpc
                      URL: /Users/501/Library/LaunchAgents/music.rpc.plist

     #6:
                     UUID: 7A000000-0000-0000-0000-000000000006
                     Name: Updater
                     Type: agent (0x8)
              Disposition: [enabled, allowed, notified] (0xb)
               Identifier: 8.com.raycast.macos.updater

     #7:
                     UUID: AP000000-0000-0000-0000-000000000007
                     Name: Apple Thing
                     Type: login item (0x4)
              Disposition: [enabled, allowed, notified] (0xb)
               Identifier: 4.com.apple.thing

    ========================
     Records for UID 0 : FFFFEEEE-DDDD-CCCC-BBBB-AAAA00000000
    ========================

     #1:
                     UUID: 22222222-0000-0000-0000-000000000001
                     Name: Root Thing
                     Type: login item (0x4)
              Disposition: [enabled, allowed, notified] (0xb)
               Identifier: 4.com.root.thing
    """

    func testParsesOnlyCurrentUsersLoginItemsAndAgents() {
        let items = BackgroundItemParser.parse(dump, uid: 501)
        XCTAssertEqual(items.map(\.identifier).sorted(), ["com.docker.helper", "com.jetson.helper", "com.raycast.macos.updater"])
    }

    func testUsesParentAppNameAndDisposition() throws {
        let items = BackgroundItemParser.parse(dump, uid: 501)
        let docker = try XCTUnwrap(items.first { $0.identifier == "com.docker.helper" })
        XCTAssertEqual(docker.name, "Docker")
        XCTAssertEqual(docker.detail, "DockerHelper")
        XCTAssertEqual(docker.developer, "Docker Inc")
        XCTAssertEqual(docker.kind, .loginItem)
        XCTAssertTrue(docker.isEnabled)
        let jetson = try XCTUnwrap(items.first { $0.identifier == "com.jetson.helper" })
        XCTAssertFalse(jetson.isEnabled)
        XCTAssertNil(jetson.detail)
        let updater = try XCTUnwrap(items.first { $0.identifier == "com.raycast.macos.updater" })
        XCTAssertEqual(updater.kind, .agent)
        XCTAssertNil(updater.developer)
    }

    func testSkipsLegacyAgentsAndAppleItems() {
        let ids = BackgroundItemParser.parse(dump, uid: 501).map(\.identifier)
        XCTAssertFalse(ids.contains("music.rpc"))
        XCTAssertFalse(ids.contains("com.apple.thing"))
    }

    func testOtherUidAndEmptyInput() {
        XCTAssertEqual(BackgroundItemParser.parse(dump, uid: 0).map(\.name), ["Root Thing"])
        XCTAssertTrue(BackgroundItemParser.parse(dump, uid: 999).isEmpty)
        XCTAssertTrue(BackgroundItemParser.parse("", uid: 501).isEmpty)
    }
}
