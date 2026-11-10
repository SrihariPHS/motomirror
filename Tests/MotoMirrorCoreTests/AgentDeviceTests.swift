import XCTest
@testable import MotoMirrorCore

final class AgentDeviceTests: XCTestCase {
    func testUIHierarchyParserReadsNodesAndBounds() throws {
        let xml = """
        <hierarchy rotation="0">
          <node index="0" text="Settings" resource-id="com.android.settings:id/home" class="android.widget.TextView" content-desc="" clickable="true" enabled="true" bounds="[0,100][1080,220]" />
          <node index="1" text="" resource-id="com.android.settings:id/search" class="android.widget.EditText" content-desc="Search settings" clickable="true" enabled="true" bounds="[100,300][900,420]" />
          <node index="2" text="Battery" class="android.widget.TextView" clickable="false" enabled="true" bounds="[0,500][400,600]" />
          <node index="3" text="bad" class="android.widget.TextView" clickable="false" enabled="true" bounds="bad" />
        </hierarchy>
        """
        let hierarchy = try UIHierarchyParser.parse(xml)
        XCTAssertEqual(hierarchy.elements.count, 3)
        XCTAssertEqual(hierarchy.elements[0].text, "Settings")
        XCTAssertTrue(hierarchy.elements[0].clickable)
        XCTAssertEqual(hierarchy.elements[0].bounds.centerX, 540)
        XCTAssertEqual(hierarchy.elements[1].contentDescription, "Search settings")
        XCTAssertEqual(hierarchy.elements[1].bounds.height, 120)
        XCTAssertEqual(hierarchy.elements[2].label, "Battery")
    }

    func testPackagesParser() {
        let output = """
        package:com.android.settings
        package:com.google.android.dialer

        """
        let apps = DeviceOutputParser.packages(output)
        XCTAssertEqual(apps.map(\.package), ["com.android.settings", "com.google.android.dialer"])
    }

    func testForegroundParser() {
        let output = """
        topResumedActivity=ActivityRecord{275ee9d u0 com.android.settings/.Settings t186}
        """
        let app = DeviceOutputParser.foreground(output)
        XCTAssertEqual(app?.package, "com.android.settings")
        XCTAssertEqual(app?.activity, ".Settings")
    }

    func testVolumeParser() {
        let output = """
        [V] volume is 15 in range [0..15]
        """
        let info = DeviceOutputParser.volume(output)
        XCTAssertEqual(info?.level, 15)
        XCTAssertEqual(info?.max, 15)
    }

    func testBoundsRejectsMalformed() {
        XCTAssertNil(UIHierarchyParser.bounds(from: "bad"))
        XCTAssertNil(UIHierarchyParser.bounds(from: "[10,20][5,10]"))
        XCTAssertEqual(
            UIHierarchyParser.bounds(from: "[10,20][110,220]"),
            UIBounds(x: 10, y: 20, width: 100, height: 200)
        )
    }
}
