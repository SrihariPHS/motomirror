import XCTest
import MotoMirrorCore

final class ScrcpyCommandTests: XCTestCase {
    func testDefaultArguments() {
        let arguments = ScrcpyCommand.arguments(serial: "ZY22ABC", options: .default)

        XCTAssertTrue(arguments.contains("--serial=ZY22ABC"))
        XCTAssertTrue(arguments.contains("--window-title=ZY22ABC — MotoMirror"))
        XCTAssertTrue(arguments.contains("--video-bit-rate=8M"))
        XCTAssertTrue(arguments.contains("--max-fps=60"))
        XCTAssertTrue(arguments.contains("--stay-awake"))
        XCTAssertFalse(arguments.contains { $0.hasPrefix("--max-size") })
        XCTAssertFalse(arguments.contains("--no-audio"))
        XCTAssertFalse(arguments.contains("--turn-screen-off"))
    }

    func testAudioDisabledAddsNoAudio() {
        var options = ScrcpyOptions.default
        options.audioEnabled = false

        XCTAssertTrue(ScrcpyCommand.arguments(serial: "ZY22ABC", options: options).contains("--no-audio"))
    }

    func testMaxSizeZeroIsOmitted() {
        var options = ScrcpyOptions.default
        options.maxSize = 0

        let arguments = ScrcpyCommand.arguments(serial: "ZY22ABC", options: options)
        XCTAssertFalse(arguments.contains { $0.hasPrefix("--max-size") })
    }

    func testArgumentsClampOutOfRangeValues() {
        var options = ScrcpyOptions.default
        options.maxSize = 8192
        options.videoBitRateMbps = 500
        options.maxFPS = 999

        let arguments = ScrcpyCommand.arguments(serial: "ZY22ABC", options: options)
        XCTAssertTrue(arguments.contains("--max-size=4096"))
        XCTAssertTrue(arguments.contains("--video-bit-rate=100M"))
        XCTAssertTrue(arguments.contains("--max-fps=240"))
    }

    func testRecordPathAddsRecordFlag() {
        let arguments = ScrcpyCommand.arguments(
            serial: "ZY22ABC",
            options: .default,
            recordPath: "/tmp/motomirror-session.mp4"
        )
        XCTAssertTrue(arguments.contains("--record=/tmp/motomirror-session.mp4"))
    }

    func testBlankRecordPathIsIgnored() {
        let arguments = ScrcpyCommand.arguments(
            serial: "ZY22ABC",
            options: .default,
            recordPath: "   "
        )
        XCTAssertFalse(arguments.contains { $0.hasPrefix("--record") })
    }

    func testWindowAndScreenFlags() {
        var options = ScrcpyOptions.default
        options.fullscreen = true
        options.alwaysOnTop = true
        options.showTouches = true
        options.turnScreenOff = true
        options.stayAwake = true

        let arguments = ScrcpyCommand.arguments(serial: "ZY22ABC", options: options)
        XCTAssertTrue(arguments.contains("--fullscreen"))
        XCTAssertTrue(arguments.contains("--always-on-top"))
        XCTAssertTrue(arguments.contains("--show-touches"))
        XCTAssertTrue(arguments.contains("--turn-screen-off"))
        XCTAssertTrue(arguments.contains("--stay-awake"))
    }

    func testTitleIncludesDeviceName() {
        let options = ScrcpyOptions.default
        XCTAssertEqual(options.windowTitle(deviceName: "moto_g85"), "moto_g85 — MotoMirror")
        XCTAssertEqual(options.windowTitle(deviceName: ""), "MotoMirror")
    }

    func testExtraArgumentsAreAppendedLast() {
        var options = ScrcpyOptions.default
        options.extraArguments = ["--no-window", "--print-fps"]

        let arguments = ScrcpyCommand.arguments(serial: "ZY22ABC", options: options)
        XCTAssertEqual(Array(arguments.suffix(2)), ["--no-window", "--print-fps"])
    }

    func testInvalidSerialIsRejected() {
        XCTAssertThrowsError(try ScrcpyCommand.validate(serial: "", options: .default)) { error in
            guard case MotoMirrorError.invalidInput = error else {
                return XCTFail("Expected invalidInput, got \(error)")
            }
        }
        XCTAssertThrowsError(try ScrcpyCommand.validate(serial: "bad serial", options: .default)) { error in
            guard case MotoMirrorError.invalidInput = error else {
                return XCTFail("Expected invalidInput, got \(error)")
            }
        }
    }

    func testInvalidBitRateIsRejected() {
        var options = ScrcpyOptions.default
        options.videoBitRateMbps = 0
        XCTAssertThrowsError(try ScrcpyCommand.validate(serial: "ZY22ABC", options: options)) { error in
            guard case MotoMirrorError.invalidInput = error else {
                return XCTFail("Expected invalidInput, got \(error)")
            }
        }
    }

    func testInvalidMaxSizeIsRejected() {
        var tooSmall = ScrcpyOptions.default
        tooSmall.maxSize = 100
        var tooLarge = ScrcpyOptions.default
        tooLarge.maxSize = 4097

        XCTAssertThrowsError(try ScrcpyCommand.validate(serial: "ZY22ABC", options: tooSmall))
        XCTAssertThrowsError(try ScrcpyCommand.validate(serial: "ZY22ABC", options: tooLarge))
        XCTAssertNoThrow(try ScrcpyCommand.validate(serial: "ZY22ABC", options: .default))
    }

    func testInvalidFPSIsRejected() {
        var negative = ScrcpyOptions.default
        negative.maxFPS = -1
        var tooFast = ScrcpyOptions.default
        tooFast.maxFPS = 241

        XCTAssertThrowsError(try ScrcpyCommand.validate(serial: "ZY22ABC", options: negative))
        XCTAssertThrowsError(try ScrcpyCommand.validate(serial: "ZY22ABC", options: tooFast))
    }
}
