import XCTest
@testable import MLXCore

/// A LoRA's strength control: regular adapters span 0...2 and never go negative,
/// negatable ones span -X...X, and the number field reaches far past the slider in both.
final class LoraRangeTests: XCTestCase {

    func testRegularRangeSpansZeroToTwoAndNeverGoesNegative() {
        XCTAssertEqual(LoraRange.regular.sliderRange, 0...2)
        XCTAssertEqual(LoraRange.regular.clamped(-5), 0)
        XCTAssertEqual(LoraRange.regular.clamped(37), 37)
        XCTAssertEqual(LoraRange.regular.clamped(1e30), LoraRange.limit)
        XCTAssertEqual(LoraRange.regular.clamped(.nan), 0)
    }

    func testNegatableRangeSpansItsBoundAndKeepsSign() {
        let r = LoraRange.negatable(20)
        XCTAssertEqual(r.sliderRange, -20...20)
        XCTAssertEqual(r.clamped(-20), -20)
        XCTAssertEqual(r.clamped(-0.35), -0.35)
        XCTAssertEqual(r.clamped(-.infinity), -LoraRange.limit)
        XCTAssertEqual(r.clamped(.nan), 0)
        // A stored bound that cannot make a slider falls back instead of building an empty one.
        XCTAssertEqual(LoraRange(signed: true, bound: .nan).sliderRange, -2...2)
        XCTAssertEqual(LoraRange(signed: true, bound: -3).sliderRange, -2...2)
        XCTAssertEqual(LoraRange(signed: true, bound: 1e9).sliderRange, -LoraRange.limit...LoraRange.limit)
    }

    func testGuessIsNegatableFromANameOrAStatedRangeOnly() {
        XCTAssertEqual(LoraRangeGuess.guess(names: ["Pornmaster_QI2.1_Breasts_Slider_V1"], description: nil), .negatable())
        XCTAssertEqual(LoraRangeGuess.guess(names: ["char-domokun"], description: nil), .regular)
        XCTAssertEqual(LoraRangeGuess.guess(names: ["photo"], description: "Works from -3 to 3."), .negatable(3))
        XCTAssertEqual(LoraRangeGuess.guess(names: ["photo"], description: "strength ±20 is fine"), .negatable(20))
        XCTAssertEqual(LoraRangeGuess.guess(names: ["photo"], description: "try −1 and 1"), .negatable(1))
        // A dash between two numbers is not a minus sign, and the word alone in a description proves nothing.
        XCTAssertEqual(LoraRangeGuess.guess(names: ["style"], description: "weights 0.6-1 to 1.2 work"), .regular)
        XCTAssertEqual(LoraRangeGuess.guess(names: ["style"], description: "not a slider, just a style"), .regular)
    }

    func testDetectReadsTheHeaderAndTheSidecarBesideTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lora-range-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let trained = dir.appendingPathComponent("concept.safetensors")
        try writeSafetensors(trained, metadata: ["trainer": "AiArtV-Slider-Trainer"])
        XCTAssertEqual(LoraRangeGuess.detect(path: trained.path), .negatable())

        let civitai = dir.appendingPathComponent("photo.safetensors")
        try writeSafetensors(civitai, metadata: [:])
        let sidecar = ["ModelName": "Detail", "ModelDescription": "<p>Runs <b>-3 to 3</b></p>"]
        try JSONSerialization.data(withJSONObject: sidecar)
            .write(to: dir.appendingPathComponent("photo.cm-info.json"))
        XCTAssertEqual(LoraRangeGuess.detect(path: civitai.path), .negatable(3))

        let plain = dir.appendingPathComponent("style.safetensors")
        try writeSafetensors(plain, metadata: ["name": "epoch_1"])
        XCTAssertEqual(LoraRangeGuess.detect(path: plain.path), .regular)
        XCTAssertEqual(LoraRangeGuess.detect(path: dir.appendingPathComponent("missing.safetensors").path), .regular)
    }

    func testARememberedRangeOutranksTheGuess() throws {
        let suite = "lora-range-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let path = "/models/lora/body_slider.safetensors"

        XCTAssertEqual(LoraRangeMemory.resolve(path: path, defaults: defaults), .negatable())
        LoraRangeMemory.remember(.negatable(20), path: path, defaults: defaults)
        XCTAssertEqual(LoraRangeMemory.resolve(path: path, defaults: defaults), .negatable(20))
        LoraRangeMemory.remember(.regular, path: path, defaults: defaults)
        XCTAssertEqual(LoraRangeMemory.resolve(path: path, defaults: defaults), .regular)
        XCTAssertEqual(LoraRangeMemory.resolve(path: "/models/lora/other.safetensors", defaults: defaults), .regular)
    }

    func testAdapterKeepsItsRangeAndAnOldBlobStillDecodes() throws {
        let a = LoraAdapter(path: "/tmp/pornmaster.safetensors", scale: -20, range: .negatable(20))
        let back = try JSONDecoder().decode(LoraAdapter.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back.range, .negatable(20))
        XCTAssertEqual(back.scale, -20)

        let old = Data(#"{"path":"/tmp/not-here.safetensors","scale":0.8}"#.utf8)
        let migrated = try JSONDecoder().decode(LoraAdapter.self, from: old)
        XCTAssertEqual(migrated.scale, 0.8)
        XCTAssertEqual(migrated.range, .regular)
    }

    private func writeSafetensors(_ url: URL, metadata: [String: String]) throws {
        let json = try JSONSerialization.data(withJSONObject: ["__metadata__": metadata])
        var length = UInt64(json.count).littleEndian
        var data = Data(bytes: &length, count: 8)
        data.append(json)
        try data.write(to: url)
    }
}
