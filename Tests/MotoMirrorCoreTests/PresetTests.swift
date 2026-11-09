import XCTest
@testable import MotoMirrorCore

final class PresetTests: XCTestCase {
    func testQualityPresetOptions() throws {
        let options = try XCTUnwrap(MirrorPreset.quality.options)

        XCTAssertEqual(options.maxSize, 1920)
        XCTAssertEqual(options.videoBitRateMbps, 12)
        XCTAssertEqual(options.maxFPS, 60)
        XCTAssertTrue(options.audioEnabled)
        XCTAssertTrue(options.stayAwake)
        XCTAssertFalse(options.turnScreenOff)
    }

    func testBalancedPresetOptions() throws {
        let options = try XCTUnwrap(MirrorPreset.balanced.options)

        XCTAssertEqual(options.maxSize, 1440)
        XCTAssertEqual(options.videoBitRateMbps, 8)
        XCTAssertEqual(options.maxFPS, 60)
        XCTAssertTrue(options.audioEnabled)
        XCTAssertTrue(options.stayAwake)
        XCTAssertFalse(options.turnScreenOff)
    }

    func testBatterySaverPresetOptions() throws {
        let options = try XCTUnwrap(MirrorPreset.batterySaver.options)

        XCTAssertEqual(options.maxSize, 720)
        XCTAssertEqual(options.videoBitRateMbps, 4)
        XCTAssertEqual(options.maxFPS, 30)
        XCTAssertFalse(options.audioEnabled)
        XCTAssertTrue(options.stayAwake)
        XCTAssertTrue(options.turnScreenOff)
    }

    func testCustomPresetHasNoFixedOptions() {
        XCTAssertNil(MirrorPreset.custom.options)
    }

    func testBalancedIsTheDefaultAndNeverUsesNativeSize() {
        XCTAssertEqual(ScrcpyOptions.default, MirrorPreset.balanced.options)
        XCTAssertEqual(ScrcpyOptions.default.maxSize, 1440)
        XCTAssertNotEqual(ScrcpyOptions.default.maxSize, 0)
        XCTAssertNoThrow(try ScrcpyCommand.validate(serial: "R5CX1234567", options: .default))
    }

    func testPresetsExposeNonEmptyDistinctMetadata() {
        for preset in MirrorPreset.allCases {
            XCTAssertFalse(preset.title.isEmpty, "\(preset.rawValue) has no title")
            XCTAssertFalse(preset.subtitle.isEmpty, "\(preset.rawValue) has no subtitle")
            XCTAssertFalse(preset.batteryNote.isEmpty, "\(preset.rawValue) has no battery note")
        }

        XCTAssertEqual(Set(MirrorPreset.allCases.map(\.title)).count, MirrorPreset.allCases.count)
    }

    func testPresetCodableRoundTrips() throws {
        for preset in MirrorPreset.allCases {
            let data = try JSONEncoder().encode(preset)
            XCTAssertEqual(try JSONDecoder().decode(MirrorPreset.self, from: data), preset)
        }
    }
}
