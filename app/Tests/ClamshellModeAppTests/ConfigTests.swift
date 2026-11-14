import XCTest
@testable import ClamshellModeApp

final class ConfigTests: XCTestCase {

    /// 老版本 config（含 phone、缺 barkKey/alertSleep/alertAwake）必须解码成功且旧值保留
    func testDecodeOldFormatJSONWithoutBarkKey() throws {
        let old = """
        {
          "fadeDuration": 2.5, "fadeEnabled": false,
          "hotkeyEnabled": true, "hotkeyKey": "7", "hotkeyMods": ["cmd"],
          "iconAwake": "bolt.fill", "iconSleep": "moon",
          "notifyDelaySec": 600, "notifyEnabled": true,
          "phone": "+15551234567", "pollInterval": 2
        }
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(ClamshellConfig.self, from: old)
        XCTAssertEqual(cfg.barkKey, "")               // 缺失的新字段 → 默认
        XCTAssertEqual(cfg.fadeDuration, 2.5)         // 旧值保留
        XCTAssertEqual(cfg.hotkeyKey, "7")
        XCTAssertEqual(cfg.notifyDelaySec, 600)
        XCTAssertTrue(cfg.notifyEnabled)
        XCTAssertEqual(cfg.alertSleep, "Clam Sleep")  // 缺失字段 → 默认（现状会整体解码失败，此为顺带修复）
    }

    func testDecodeEmptyJSONGivesDefaults() throws {
        let cfg = try JSONDecoder().decode(ClamshellConfig.self, from: "{}".data(using: .utf8)!)
        XCTAssertEqual(cfg, ClamshellConfig())
    }

    func testEncodeContainsBarkKeyAndNoPhone() throws {
        var cfg = ClamshellConfig()
        cfg.barkKey = "testkey123"
        let json = String(data: try JSONEncoder().encode(cfg), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"barkKey\""))
        XCTAssertFalse(json.contains("\"phone\""))
    }

    /// 合盖省电两个开关：默认关；老 JSON 没这两个键时也是关；打开后能原样读回
    func testLidPowerSavingTogglesDefaultOffAndRoundTrip() throws {
        XCTAssertFalse(ClamshellConfig().lidCloseDisplaySleep)
        XCTAssertFalse(ClamshellConfig().lidCloseLowPower)

        let old = try JSONDecoder().decode(ClamshellConfig.self, from: #"{"fadeDuration": 2.5}"#.data(using: .utf8)!)
        XCTAssertFalse(old.lidCloseDisplaySleep)
        XCTAssertFalse(old.lidCloseLowPower)

        var cfg = ClamshellConfig()
        cfg.lidCloseDisplaySleep = true
        cfg.lidCloseLowPower = true
        let back = try JSONDecoder().decode(ClamshellConfig.self, from: try JSONEncoder().encode(cfg))
        XCTAssertTrue(back.lidCloseDisplaySleep)
        XCTAssertTrue(back.lidCloseLowPower)
    }
}
