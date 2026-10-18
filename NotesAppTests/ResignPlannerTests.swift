import XCTest
@testable import NotesApp

final class ResignPlannerTests: XCTestCase {
    private func d(_ text: String) -> Date { TestCalendar.date(text) }

    /// Профиль бесплатной подписи: мусор подписи вокруг обычного plist.
    func testReadsExpirationFromProfile() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>AppIDName</key><string>Mysli</string>
        <key>ExpirationDate</key><date>2026-10-24T09:31:00Z</date></dict></plist>
        """
        var data = Data([0x30, 0x82, 0x0F, 0x00, 0x06, 0x09])
        data.append(Data(plist.utf8))
        data.append(Data([0xA0, 0x82, 0x01]))

        let expected = ISO8601DateFormatter().date(from: "2026-10-24T09:31:00Z")
        XCTAssertEqual(ProvisionInfo.expiration(fromProfile: data), expected)
        XCTAssertNil(ProvisionInfo.expiration(fromProfile: Data("нет профиля".utf8)))
    }

    func testRemindsADayBefore() {
        let plan = ResignPlanner.plan(expiration: d("2026-10-24 12:30"), now: d("2026-10-17 12:00"))
        XCTAssertEqual(plan?.date, d("2026-10-23 12:30"))
        XCTAssertEqual(plan?.id, "resign-reminder")
    }

    func testLateStillRemindsTwoHoursBefore() {
        let plan = ResignPlanner.plan(expiration: d("2026-10-24 12:30"), now: d("2026-10-24 01:00"))
        XCTAssertEqual(plan?.date, d("2026-10-24 10:30"))
    }

    func testNothingWithoutProfileOrWhenExpired() {
        XCTAssertNil(ResignPlanner.plan(expiration: nil, now: d("2026-10-17 12:00")))
        XCTAssertNil(ResignPlanner.plan(expiration: d("2026-10-17 11:00"), now: d("2026-10-17 12:00")))
    }

    func testBannerInLastTwoDays() {
        XCTAssertFalse(ResignPlanner.needsBanner(expiration: d("2026-10-24 12:30"), now: d("2026-10-17 12:00")))
        XCTAssertTrue(ResignPlanner.needsBanner(expiration: d("2026-10-24 12:30"), now: d("2026-10-23 08:00")))
    }
}
