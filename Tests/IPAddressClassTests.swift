import XCTest
@testable import Adalmon

final class IPAddressClassTests: XCTestCase {
    func testIPv4Classes() {
        let cases: [(String, IPAddressClass)] = [
            ("127.0.0.1", .loopback), ("127.255.1.2", .loopback),
            ("10.0.0.5", .privateNetwork), ("192.168.1.148", .privateNetwork),
            ("172.16.0.1", .privateNetwork), ("172.31.255.255", .privateNetwork),
            ("172.15.0.1", .publicAddress), ("172.32.0.1", .publicAddress),
            ("192.169.0.1", .publicAddress), ("11.0.0.1", .publicAddress),
            ("169.254.10.20", .linkLocal),
            ("100.64.0.1", .sharedAddressSpace), ("100.127.255.255", .sharedAddressSpace), ("100.128.0.1", .publicAddress),
            ("224.0.0.251", .multicast), ("0.0.0.0", .unspecified), ("255.255.255.255", .reserved),
            ("160.79.104.10", .publicAddress), ("8.8.8.8", .publicAddress),
        ]
        for (ip, expected) in cases { XCTAssertEqual(IPAddressClass.classify(ip), expected, ip) }
    }

    func testIPv6Classes() {
        let cases: [(String, IPAddressClass)] = [
            ("::1", .loopback), ("::", .unspecified),
            ("fe80::ec:fd1e:f9c4:435c", .linkLocal), ("fe80::ec:fd1e:f9c4:435c%en0", .linkLocal), ("[fe80::1]", .linkLocal),
            ("febf::1", .linkLocal),
            ("fc00::1", .privateNetwork), ("fd12:3456::1", .privateNetwork),
            ("ff02::fb", .multicast),
            ("2001:4860:4860::8888", .publicAddress), ("2a00:1450:4001::1", .publicAddress),
            ("::ffff:192.168.1.5", .privateNetwork), ("::ffff:8.8.8.8", .publicAddress), ("::ffff:127.0.0.1", .loopback),
        ]
        for (ip, expected) in cases { XCTAssertEqual(IPAddressClass.classify(ip), expected, ip) }
    }

    func testNonIPsAreRejected() {
        for s in ["example.com", "abc.def", "1.2.3", "1.2.3.4.5", "256.1.1.1", "YouTube", "", "?", "Yerel ağ", "deadbeef"] {
            XCTAssertNil(IPAddressClass.classify(s), s)
        }
    }

    func testParsedTextIsNormalized() {
        XCTAssertEqual(IPAddressClass.parse("[2001:DB8::1]")?.text, "2001:db8::1")
        XCTAssertEqual(IPAddressClass.parse("::ffff:8.8.8.8")?.text, "8.8.8.8")
        XCTAssertEqual(IPAddressClass.parse("fe80::1%en0")?.text, "fe80::1")
    }

    func testIsLocalNetwork() {
        XCTAssertTrue(IPAddressClass.privateNetwork.isLocalNetwork)
        XCTAssertTrue(IPAddressClass.linkLocal.isLocalNetwork)
        XCTAssertFalse(IPAddressClass.publicAddress.isLocalNetwork)
        XCTAssertFalse(IPAddressClass.loopback.isLocalNetwork)
    }
}
