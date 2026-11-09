import XCTest
@testable import MotoMirrorCore

final class DeviceListNormalizerTests: XCTestCase {
    private let mdnsSerial = "adb-R5CX1234567-AbCdEf._adb-tls-connect._tcp"
    private let ipSerial = "192.168.1.42:37819"

    func testBothOnlineKeepsMDNS() {
        let mdns = device(mdnsSerial, state: .device)
        let ip = device(ipSerial, state: .device)

        XCTAssertEqual(DeviceListNormalizer.normalize([ip, mdns]), [mdns])
    }

    func testOnlineIPAliasBeatsOfflineMDNS() {
        let mdns = device(mdnsSerial, state: .offline)
        let ip = device(ipSerial, state: .device)

        XCTAssertEqual(DeviceListNormalizer.normalize([mdns, ip]), [ip])
    }

    func testBothOfflineKeepsMDNS() {
        let mdns = device(mdnsSerial, state: .offline)
        let ip = device(ipSerial, state: .offline)

        XCTAssertEqual(DeviceListNormalizer.normalize([ip, mdns]), [mdns])
    }

    func testDeviceMDNSBeatsUnauthorizedIPAlias() {
        let mdns = device(mdnsSerial, state: .device)
        let ip = device(ipSerial, state: .unauthorized)

        XCTAssertEqual(DeviceListNormalizer.normalize([mdns, ip]), [mdns])
    }

    func testUnauthorizedIPAliasBeatsOfflineMDNS() {
        let mdns = device(mdnsSerial, state: .offline)
        let ip = device(ipSerial, state: .unauthorized)

        XCTAssertEqual(DeviceListNormalizer.normalize([mdns, ip]), [ip])
    }

    func testUnauthorizedMDNSBeatsOfflineIPAlias() {
        let mdns = device(mdnsSerial, state: .unauthorized)
        let ip = device(ipSerial, state: .offline)

        XCTAssertEqual(DeviceListNormalizer.normalize([ip, mdns]), [mdns])
    }

    func testMDNSWinsOverOfflineIPAlias() {
        let mdns = device(mdnsSerial, state: .device)
        let ip = device(ipSerial, state: .offline)

        XCTAssertEqual(DeviceListNormalizer.normalize([mdns, ip]), [mdns])
    }

    func testIPAliasWithoutMDNSIsKept() {
        let ip = device(ipSerial, state: .device)

        XCTAssertEqual(DeviceListNormalizer.normalize([ip]), [ip])
    }

    func testTwoUSBDevicesWithSameModelAreBothKept() {
        let first = device("R5CX1234567", model: "moto_g85", product: "moto_g85", transport: .usb)
        let second = device("ZY22OTHER", model: "moto_g85", product: "moto_g85", transport: .usb)

        XCTAssertEqual(DeviceListNormalizer.normalize([first, second]), [first, second])
    }

    func testDifferentModelsAreBothKept() {
        let mdns = device(mdnsSerial, model: "moto_g85", product: "moto_g85")
        let ip = device(ipSerial, model: "pixel_8", product: "pixel_8")

        XCTAssertEqual(DeviceListNormalizer.normalize([mdns, ip]), [mdns, ip])
    }

    func testPreservesInputOrderOfWinningEntries() {
        let usb = device("R5CX1234567", model: "moto_g85", product: "moto_g85", transport: .usb)
        let ip = device(ipSerial, state: .device)
        let mdns = device(mdnsSerial, state: .device)
        let secondUSB = device("ZY22OTHER", model: "moto_g85", product: "moto_g85", transport: .usb)

        XCTAssertEqual(
            DeviceListNormalizer.normalize([usb, ip, mdns, secondUSB]),
            [usb, mdns, secondUSB]
        )
    }

    func testConflictingProductsPreventMerge() {
        let mdns = device(mdnsSerial, model: "moto_g85", product: "moto_g85")
        let ip = device(ipSerial, model: "moto_g85", product: "other_product")

        XCTAssertEqual(DeviceListNormalizer.normalize([mdns, ip]), [mdns, ip])
    }

    func testMissingIdentityDoesNotMergeAliases() {
        let mdns = device(mdnsSerial, model: nil, product: nil)
        let ip = device(ipSerial, model: nil, product: nil)

        XCTAssertEqual(DeviceListNormalizer.normalize([mdns, ip]), [mdns, ip])
    }

    func testProductAloneCanIdentifyTheSamePhone() {
        let mdns = device(mdnsSerial, model: nil, product: "moto_g85")
        let ip = device(ipSerial, model: "moto_g85", product: "moto_g85")

        XCTAssertEqual(DeviceListNormalizer.normalize([ip, mdns]), [mdns])
    }

    private func device(
        _ serial: String,
        state: AndroidDevice.State = .device,
        model: String? = "moto_g85",
        product: String? = "moto_g85",
        transport: AndroidDevice.Transport = .wireless
    ) -> AndroidDevice {
        AndroidDevice(
            serial: serial,
            state: state,
            model: model,
            product: product,
            transport: transport
        )
    }
}
