import XCTest

final class CoreTests: XCTestCase {
    private let today = Day(year: 2026, month: 11, day: 24)


    func testParsesUSReceipt() {
        let lines = ["COSTCO WHOLESALE", "BOSCH DISHWASHER", "SHPM65Z55N", "SUBTOTAL 849.99", "TAX 69.12", "TOTAL 919.11", "12/08/2024 14:32", "THANK YOU"]
        let p = ReceiptParser.parse(lines, today: today)
        XCTAssertEqual(p.store, "COSTCO WHOLESALE")
        XCTAssertEqual(p.date, Day(year: 2024, month: 12, day: 8))
        XCTAssertEqual(p.amount, "919.11")
        XCTAssertEqual(p.name, "Bosch Dishwasher")
        XCTAssertEqual(p.model, "SHPM65Z55N")
    }

    func testItemNameSkipsNoiseAndKeepsChinese() {
        let p = ReceiptParser.parse(["BEST BUY #1234", "Cashier: Amy", "Sony WH-1000XM5 Headphones", "TOTAL 349.99"], today: today)
        XCTAssertEqual(p.name, "Sony WH-1000XM5 Headphones")
        let zh = ReceiptParser.parse(["苏宁易购 南京店", "电话 025-12345678", "美的 空调 KFR-35GW", "合计：2,999.00"], today: today)
        XCTAssertEqual(zh.name, "美的 空调 KFR-35GW")
        XCTAssertNil(ReceiptParser.parse(["SHOP", "ITEM 12.00"], today: today).name)
    }

    func testParsesChineseAndJapaneseFormats() {
        let zh = ReceiptParser.parse(["苏宁易购 南京店", "电话 025-12345678", "合计：1,299.00", "2025年3月7日 18:20"], today: today)
        XCTAssertEqual(zh.store, "苏宁易购 南京店")
        XCTAssertEqual(zh.date, Day(year: 2025, month: 3, day: 7))
        XCTAssertEqual(zh.amount, "1299.00")
        let jp = ReceiptParser.parse(["ヨドバシカメラ", "2026/01/15", "合 計 ¥12,800.00"], today: today)
        XCTAssertEqual(jp.date, Day(year: 2026, month: 1, day: 15))
        XCTAssertEqual(jp.amount, "12800.00")
    }

    func testDayFirstAndEuropeanDatesAndMonthNames() {
        XCTAssertEqual(ReceiptParser.dates(in: "25/03/2025").first, Day(year: 2025, month: 3, day: 25))
        XCTAssertEqual(ReceiptParser.dates(in: "08.12.2024").first, Day(year: 2024, month: 12, day: 8))
        XCTAssertEqual(ReceiptParser.dates(in: "Dec 8, 2024").first, Day(year: 2024, month: 12, day: 8))
        XCTAssertEqual(ReceiptParser.dates(in: "8 December 2024").first, Day(year: 2024, month: 12, day: 8))
        XCTAssertTrue(ReceiptParser.dates(in: "13/13/2024").isEmpty)
        XCTAssertTrue(ReceiptParser.dates(in: "Call 1-800-944-2904").isEmpty)
    }

    func testFutureDatesAndMissingTotalFallBack() {
        let p = ReceiptParser.parse(["SHOP", "RETURN BY 01/30/2027", "11/20/2026", "ITEM 12.00", "ITEM 40.50"], today: today)
        XCTAssertEqual(p.date, Day(year: 2026, month: 11, day: 20))
        XCTAssertEqual(p.amount, "40.50")
        XCTAssertEqual(ReceiptParser.parse(["12345 6789"], today: today), ParsedReceipt())
    }


    func testWarrantyEndClampsMonthEndAndLeapDay() {
        var i = Item()
        i.purchased = Day(year: 2024, month: 1, day: 31); i.warrantyMonths = 1
        XCTAssertEqual(i.warrantyEnd, Day(year: 2024, month: 2, day: 29))
        i.purchased = Day(year: 2024, month: 2, day: 29); i.warrantyMonths = 12
        XCTAssertEqual(i.warrantyEnd, Day(year: 2025, month: 2, day: 28))
        i.warrantyMonths = nil
        XCTAssertNil(i.warrantyEnd)
    }

    func testDeadlinesOrderAndNextAndActive() {
        var i = Item()
        i.purchased = Day(year: 2026, month: 11, day: 1); i.warrantyMonths = 12; i.returnDays = 30
        i.extendedEnd = Day(year: 2029, month: 11, day: 1)
        XCTAssertEqual(i.deadlines.map(\.kind), [.returnWindow, .warranty, .extended])
        XCTAssertEqual(i.next(after: today)?.kind, .returnWindow)
        XCTAssertEqual(i.next(after: Day(year: 2026, month: 12, day: 2))?.kind, .warranty)
        XCTAssertTrue(i.active(on: Day(year: 2028, month: 1, day: 1)))
        XCTAssertFalse(i.active(on: Day(year: 2030, month: 1, day: 1)))
        i.extendedEnd = Day(year: 2027, month: 1, day: 1)
        XCTAssertFalse(i.deadlines.contains { $0.kind == .extended })
    }

    func testDocumentsUseExpiryOnly() {
        var d = Item()
        d.category = "document"; d.purchased = today; d.warrantyMonths = 12; d.expires = Day(year: 2027, month: 4, day: 1)
        XCTAssertEqual(d.deadlines, [Deadline(kind: .document, day: Day(year: 2027, month: 4, day: 1))])
    }

    func testSortingPutsSoonestFirstAndExpiredLast() {
        var a = Item(); a.name = "A"; a.purchased = Day(year: 2026, month: 1, day: 1); a.warrantyMonths = 12
        var b = Item(); b.name = "B"; b.purchased = Day(year: 2025, month: 12, day: 1); b.warrantyMonths = 12
        var old = Item(); old.name = "Old"; old.purchased = Day(year: 2020, month: 1, day: 1); old.warrantyMonths = 12
        var s = AppState(); s.items = [old, a, b]
        XCTAssertEqual(s.sorted(on: today).map(\.name), ["B", "A", "Old"])
        XCTAssertEqual(s.soon(on: today).map(\.name), ["B"])
    }

    func testRemainingText() {
        XCTAssertEqual(Remaining.text(from: today, to: today), L.t("left.today"))
        XCTAssertEqual(Remaining.text(from: today, to: today.adding(days: 14)), L.f("left.days", 14))
        XCTAssertEqual(Remaining.text(from: today, to: today.adding(months: 19)), L.f("left.yearsMonths", 1, 7))
        XCTAssertEqual(Remaining.text(from: today, to: today.adding(days: -1)), L.t("left.expired"))
    }


    func testReminderPlanSkipsPastAndUsesLeadDays() {
        var i = Item(); i.purchased = Day(year: 2026, month: 11, day: 20); i.warrantyMonths = 12; i.returnDays = 30
        var s = AppState(); s.items = [i]
        let plan = ReminderPlan.plan(s, today: today)
        XCTAssertEqual(plan.map(\.day), [Day(year: 2026, month: 12, day: 17), Day(year: 2027, month: 11, day: 6), Day(year: 2027, month: 11, day: 19)])
        XCTAssertEqual(plan.first?.kind, .returnWindow)
        XCTAssertEqual(ReminderPlan.plan(s, today: Day(year: 2027, month: 11, day: 10)).count, 1)
    }

    func testReminderPlanCapsAt60() {
        var s = AppState()
        for n in 0..<40 { var i = Item(); i.purchased = today.adding(days: n); i.warrantyMonths = 12; s.items.append(i) }
        XCTAssertEqual(ReminderPlan.plan(s, today: today).count, 60)
    }


    func testFreeLimitAndTrial() {
        var s = AppState()
        s.items = Array(repeating: Item(), count: Launch.freeLimit)
        XCTAssertFalse(s.canAdd(hasPro: false))
        XCTAssertTrue(s.canAdd(hasPro: true))
        var e = Entitlement(); e.firstOpen = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(e.hasPro(at: Date(timeIntervalSince1970: 29 * 86_400)))
        XCTAssertFalse(e.hasPro(at: Date(timeIntervalSince1970: 31 * 86_400)))
        e.purchasedPro = true
        XCTAssertTrue(e.hasPro(at: Date(timeIntervalSince1970: 400 * 86_400)))
    }


    func testTransferRoundTripInsideChatText() throws {
        var i = Item(); i.name = "Dishwasher"; i.store = "Costco"; i.purchased = Day(year: 2024, month: 12, day: 8)
        i.warrantyMonths = 24; i.returnDays = 30; i.model = "SHPM65Z55N"; i.photos = ["x.jpg"]
        let text = "看这个 " + Transfer.code(for: i) + "\nPaste this"
        let back = try Transfer.item(from: text, categories: CategoryDef.presets)
        XCTAssertEqual(back.name, "Dishwasher")
        XCTAssertEqual(back.warrantyEnd, Day(year: 2026, month: 12, day: 8))
        XCTAssertEqual(back.model, "SHPM65Z55N")
        XCTAssertTrue(back.photos.isEmpty)
        XCTAssertNotEqual(back.id, i.id)
    }

    func testTransferRejectsGarbage() {
        for bad in ["", "hello", "WTK1:", "WTK1:!!!!", "WTK1:" + Data("{\"name\":1}".utf8).base64EncodedString()] {
            XCTAssertThrowsError(try Transfer.item(from: bad, categories: CategoryDef.presets), bad)
        }
    }

    func testCSVEscapesFormulasAndQuotes() {
        XCTAssertEqual(CSVExport.cell("=SUM(A1)"), "'=SUM(A1)")
        XCTAssertEqual(CSVExport.cell("a,\"b\""), "\"a,\"\"b\"\"\"")
        var i = Item(); i.name = "+cmd"; i.notes = "line1\nline2"; i.purchased = today
        var s = AppState(); s.items = [i]
        let csv = CSVExport.text(s)
        XCTAssertTrue(csv.contains("'+cmd"))
        XCTAssertTrue(csv.contains("\"line1\nline2\""))
        XCTAssertEqual(csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 2)
    }

    func testStateRoundTripsThroughJSON() throws {
        var s = AppState()
        var i = Item(); i.purchased = today; i.extendedEnd = today.adding(months: 30); i.saved = 240
        s.items = [i]; s.categories.append(CategoryDef(id: "c1", custom: "Garage"))
        let data = try Store.encoder.encode(s)
        let back = try Store.decoder.decode(AppState.self, from: data)
        XCTAssertEqual(back.items.first?.extendedEnd, today.adding(months: 30))
        XCTAssertEqual(back.category("c1").title, "Garage")
        XCTAssertEqual(back.category("missing").id, "other")
    }
}
