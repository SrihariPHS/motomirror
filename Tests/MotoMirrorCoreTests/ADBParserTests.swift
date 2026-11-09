import XCTest
@testable import MotoMirrorCore

final class ADBParserTests: XCTestCase {
    // MARK: - Devices

    func testParsesUSBDeviceWithMetadata() {
        let output = """
        List of devices attached
        R5CX1234567	device product:moto_g85 model:moto_g85 device:g85 usb:1-4 transport_id:1

        """

        let devices = ADBParser.parseDevices(output)

        XCTAssertEqual(devices.count, 1)
        let device = devices[0]
        XCTAssertEqual(device.serial, "R5CX1234567")
        XCTAssertEqual(device.state, .device)
        XCTAssertEqual(device.model, "moto_g85")
        XCTAssertEqual(device.product, "moto_g85")
        XCTAssertEqual(device.device, "g85")
        XCTAssertEqual(device.transport, .usb)
        XCTAssertTrue(device.isUsable)
    }

    func testParsesWirelessDeviceByColonInSerial() {
        let output = "192.168.1.42:5555\tdevice product:moto_g85 model:moto_g85 device:g85 transport_id:3"

        let devices = ADBParser.parseDevices(output)

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].serial, "192.168.1.42:5555")
        XCTAssertEqual(devices[0].transport, .wireless)
        XCTAssertEqual(devices[0].state, .device)
    }

    func testParsesUnauthorizedAndOfflineStates() {
        let output = """
        List of devices attached
        ZY22ABCDEF	unauthorized usb:1-2 transport_id:2
        ZY22GHIJKL	offline usb:2-1 transport_id:4

        """

        let devices = ADBParser.parseDevices(output)

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].state, .unauthorized)
        XCTAssertEqual(devices[1].state, .offline)
        XCTAssertFalse(devices[0].isUsable)
        XCTAssertFalse(devices[1].isUsable)
    }

    func testParsesAuthorizingAndConnectingStates() {
        let output = """
        adb-ABC._adb-tls-connect._tcp	authorizing
        192.168.1.42:5555	connecting

        """

        let devices = ADBParser.parseDevices(output)

        XCTAssertEqual(devices.map(\.state), [.authorizing, .connecting])
    }

    func testSkipsHeaderDaemonNoticesAndBlankLines() {
        let output = """

        * daemon not running; starting now at tcp:5037
        * daemon started successfully
        List of devices attached
        R5CX1234567	device usb:1-4 transport_id:1

        """

        let devices = ADBParser.parseDevices(output)

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].serial, "R5CX1234567")
    }

    func testHandlesCRLFOutput() {
        let output = "List of devices attached\r\nR5CX1234567\tdevice usb:1-4 transport_id:1\r\n192.168.1.42:5555\tdevice\r\n"

        let devices = ADBParser.parseDevices(output)

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].serial, "R5CX1234567")
        XCTAssertEqual(devices[0].transport, .usb)
        XCTAssertEqual(devices[1].serial, "192.168.1.42:5555")
        XCTAssertEqual(devices[1].transport, .wireless)
    }

    func testNoPermissionsLineBecomesUnknownDevice() {
        let output = """
        ????????????\tno permissions (user in plugdev group; are your udev rules wrong?); see [http://developer.android.com/tools/device.html]
        ???????????? no permissions (user in plugdev group; are your udev rules wrong?)

        """

        let devices = ADBParser.parseDevices(output)

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].serial, "????????????")
        XCTAssertEqual(devices[0].state, .unknown)
        XCTAssertEqual(devices[0].transport, .unknown)
        XCTAssertEqual(devices[1].serial, "????????????")
        XCTAssertEqual(devices[1].state, .unknown)
    }

    func testMalformedLinesDoNotCrash() {
        let output = """
        List of devices attached
        only-a-serial
        SERIAL	recovery usb:3-1
        SERIAL2	
        \tdevice usb:1-1

        """

        let devices = ADBParser.parseDevices(output)

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].serial, "SERIAL")
        XCTAssertEqual(devices[0].state, .unknown)
        XCTAssertEqual(devices[0].transport, .usb)
    }

    func testTransportIsUnknownWithoutUsbMetadataOrColon() {
        let output = "adb-ABC._adb-tls-connect._tcp\tdevice"

        let devices = ADBParser.parseDevices(output)

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].transport, .unknown)
    }

    // MARK: - getprop

    func testParsesGetPropValuesWithSpacesAndBrackets() {
        let output = """
        [ro.product.manufacturer]: [motorola]
        [ro.product.model]: [moto g85 5G]
        [ro.build.version.release]: [14]
        [ro.build.version.sdk]: [34]
        [ro.product.cpu.abi]: [arm64-v8a]
        [persist.sys.timezone]: [America/New York]
        [ro.weird.value]: [a [nested] value]
        """

        let properties = ADBParser.parseGetProp(output)

        XCTAssertEqual(properties["ro.product.manufacturer"], "motorola")
        XCTAssertEqual(properties["ro.product.model"], "moto g85 5G")
        XCTAssertEqual(properties["ro.build.version.release"], "14")
        XCTAssertEqual(properties["ro.build.version.sdk"], "34")
        XCTAssertEqual(properties["ro.product.cpu.abi"], "arm64-v8a")
        XCTAssertEqual(properties["persist.sys.timezone"], "America/New York")
        XCTAssertEqual(properties["ro.weird.value"], "a [nested] value")
        XCTAssertEqual(properties.count, 7)
    }

    func testIgnoresMalformedGetPropLines() {
        let output = """
        not a property
        [key]: value-without-brackets
        [unterminated: [value]
        [good.key]: [good value]

        """

        let properties = ADBParser.parseGetProp(output)

        XCTAssertEqual(properties, ["good.key": "good value"])
    }

    // MARK: - Battery

    func testParsesBatteryLevelStatusTemperatureAndVoltage() {
        let output = """
        Current Battery Service state:
          AC powered: false
          USB powered: true
          status: 2
          health: 2
          present: true
          level: 85
          scale: 100
          voltage: 4200
          temperature: 310
          technology: Li-ion

        """

        let battery = ADBParser.parseBattery(output)

        XCTAssertEqual(battery?.level, 85)
        XCTAssertEqual(battery?.status, "Charging")
        XCTAssertEqual(battery?.temperatureCelsius, 31.0)
        XCTAssertEqual(battery?.voltageMillivolts, 4200)
        XCTAssertEqual(battery?.isCharging, true)
    }

    func testMapsEveryBatteryStatus() {
        let cases: [(Int, String, Bool)] = [
            (1, "Unknown", false),
            (2, "Charging", true),
            (3, "Discharging", false),
            (4, "Not charging", false),
            (5, "Full", true)
        ]

        for (raw, expected, charging) in cases {
            let battery = ADBParser.parseBattery("level: 50\nstatus: \(raw)")
            XCTAssertEqual(battery?.status, expected, "status \(raw)")
            XCTAssertEqual(battery?.isCharging, charging, "status \(raw)")
        }
    }

    func testBatteryRequiresUsableLevel() {
        XCTAssertNil(ADBParser.parseBattery("status: 2\ntemperature: 310"))
        XCTAssertNil(ADBParser.parseBattery("level: 150\nstatus: 2"))
        XCTAssertNil(ADBParser.parseBattery(""))
    }

    func testParsesNegativeBatteryTemperature() {
        let battery = ADBParser.parseBattery("level: 12\ntemperature: -50")

        XCTAssertEqual(battery?.temperatureCelsius, -5.0)
    }

    // MARK: - Storage

    func testParsesDataPartitionStorage() {
        let output = """
        Filesystem       1K-blocks      Used  Available Use% Mounted on
        /dev/block/dm-6  115343360  45678900   69664460  40% /data

        """

        let storage = ADBParser.parseStorage(output)

        XCTAssertEqual(storage?.totalBytes, 115343360 * 1024)
        XCTAssertEqual(storage?.availableBytes, 69664460 * 1024)
        XCTAssertEqual(storage?.usedBytes, 45678900 * 1024)
    }

    func testParsesAndroid15DataUserMountPoint() {
        let output = """
        Filesystem       1K-blocks    Used Available Use% Mounted on
        /dev/block/dm-44  10167132 1315148   8704528  14% /data/user/0

        """

        let storage = ADBParser.parseStorage(output)

        XCTAssertEqual(storage?.totalBytes, 10167132 * 1024)
        XCTAssertEqual(storage?.availableBytes, 8704528 * 1024)
        XCTAssertEqual(storage?.usedBytes, (10167132 - 8704528) * 1024)
    }

    func testStorageIgnoresLookalikeMountPoints() {
        let output = """
        Filesystem       1K-blocks    Used Available Use% Mounted on
        /dev/block/dm-6  115343360  45678900  69664460  40% /database
        /dev/block/dm-7  115343360  45678900  69664460  40% /data.bak

        """

        XCTAssertNil(ADBParser.parseStorage(output))
    }

    func testStorageReturnsNilWhenDataLineIsAbsent() {
        let output = """
        Filesystem       1K-blocks      Used  Available Use% Mounted on
        /dev/block/dm-6  115343360  45678900   69664460  40% /

        """

        XCTAssertNil(ADBParser.parseStorage(output))
        XCTAssertNil(ADBParser.parseStorage("df: /data: Permission denied"))
    }

    // MARK: - Screen

    func testParsesPhysicalScreenSize() {
        let screen = ADBParser.parseScreen("Physical size: 1080x2400")

        XCTAssertEqual(screen?.width, 1080)
        XCTAssertEqual(screen?.height, 2400)
        XCTAssertNil(screen?.density)
    }

    func testPrefersOverrideSizeAndOverrideDensity() {
        let output = """
        Physical size: 1080x2400
        Override size: 720x1600
        Physical density: 420
        Override density: 400

        """

        let screen = ADBParser.parseScreen(output)

        XCTAssertEqual(screen, ScreenInfo(width: 720, height: 1600, density: 400))
    }

    func testParsesDensitySeparately() {
        XCTAssertEqual(ADBParser.parseDensity("Physical density: 420"), 420)
        XCTAssertEqual(
            ADBParser.parseDensity("Physical density: 420\nOverride density: 400"),
            400
        )
        XCTAssertNil(ADBParser.parseDensity("Physical size: 1080x2400"))
    }

    func testScreenReturnsNilWhenNoSizeIsPresent() {
        XCTAssertNil(ADBParser.parseScreen("Physical density: 420"))
        XCTAssertNil(ADBParser.parseScreen(""))
    }
}
