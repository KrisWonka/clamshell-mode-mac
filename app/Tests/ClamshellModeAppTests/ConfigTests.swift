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
}
