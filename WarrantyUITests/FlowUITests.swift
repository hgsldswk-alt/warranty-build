import XCTest

final class FlowUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    func testCaptureSavesInTwoTapsAndReadsReceipt() {
        launch()
        XCTAssertTrue(wait("list.empty").exists)
        tap("list.capture")
        tap("camera.shutter")
        XCTAssertTrue(wait("editor.saved", timeout: 20).exists)
        let price = wait("editor.price")
        XCTAssertEqual(price.value as? String, "919.11")
        tap("editor.done")
        XCTAssertTrue(wait("row.0").exists)
        XCTAssertTrue(element("row.0").label.contains("Bosch Dishwasher"), element("row.0").label)
    }

    func testDemoListSortedDetailAndFixedShareCard() {
        launch(["-demo"])
        XCTAssertTrue(wait("list.soon").exists)
        let first = wait("row.0")
        XCTAssertTrue(first.label.contains("Bosch") || first.label.contains("Noise"), first.label)
        tap("row.0")
        XCTAssertTrue(wait("detail.until").exists)
        tap("detail.fixed", slide: true)
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.typeText("240")
        tapAlertConfirm()
        XCTAssertTrue(wait("share.card", timeout: 15).exists)
        tap("share.done")
    }

    func testFreeLimitSendsToPaywallButKeepsItems() {
        launch(["-demo", "-expired"])
        XCTAssertTrue(wait("list.free").exists)
        tap("list.capture")
        XCTAssertTrue(wait("paywall.status", timeout: 8).exists)
        tap("paywall.close")
        XCTAssertTrue(wait("row.4").exists)
    }

    func testManualAddCategoryFilterAndDelete() {
        launch(["-demo"])
        tap("chip.document")
        XCTAssertTrue(wait("row.0").label.contains("Passport"))
        XCTAssertFalse(element("row.1").exists)
        tap("chip.all")
        tap("list.manual")
        XCTAssertTrue(wait("editor.saved").exists)
        tap("editor.delete", slide: true)
        let sheetButton = app.sheets.buttons["Delete this item"]
        if sheetButton.waitForExistence(timeout: 5) { sheetButton.tap() }
        else { app.buttons.matching(NSPredicate(format: "label == %@", "Delete this item")).allElementsBoundByIndex.last?.tap() }
        XCTAssertTrue(wait("row.4").exists)
        XCTAssertFalse(element("row.5").exists)
    }

    func testSearchAndExpiredSinkToBottom() {
        launch(["-demo", "-demo-old", "-paid"])
        XCTAssertTrue(wait("list.expiredHeader").exists)
        XCTAssertTrue(element("row.5").label.contains("Blender"), element("row.5").label)
        let field = wait("list.search")
        field.tap()
        field.typeText("shpm65")
        XCTAssertTrue(wait("row.0").label.contains("Dishwasher") || element("row.0").label.contains("Bosch"), element("row.0").label)
        XCTAssertFalse(element("row.1").exists)
        field.typeText("zzz")
        XCTAssertTrue(wait("list.noMatch").exists)
    }

    func testExportReadyAndNotificationsDeniedDoNotBlock() {
        launch(["-demo", "-notifications-denied"])
        XCTAssertTrue(wait("list.notificationsOff").exists)
        tap("list.settings")
        tap("export.csv")
        XCTAssertTrue(wait("export.ready", timeout: 8).exists)
        XCTAssertTrue(wait("settings.denied", slide: true).exists)
    }

    func testImportRejectsBadCodeAndKeepsList() {
        launch()
        tap("list.import")
        let field = wait("import.field")
        field.tap()
        field.typeText("WTK1:broken")
        tap("import.go")
        XCTAssertTrue(wait("import.error").exists)
        XCTAssertTrue(wait("import.field").exists)
    }

    func testStoreScreenshots() {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            launch(["-demo"], language: language)
            XCTAssertTrue(wait("row.0").exists)
            shot("store-\(language)-01-list")

            launch(["-capture"], language: language)
            XCTAssertTrue(wait("camera.shutter").exists)
            shot("store-\(language)-02-capture")
            tap("camera.shutter")
            XCTAssertTrue(wait("editor.saved", timeout: 20).exists)
            shot("store-\(language)-03-saved")

            launch(["-demo"], language: language)
            tap("row.0")
            XCTAssertTrue(wait("detail.until").exists)
            shot("store-\(language)-04-detail")
            tap("detail.fixed", slide: true)
            let field = app.alerts.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 6))
            field.typeText("240")
            tapAlertConfirm()
            XCTAssertTrue(wait("share.card", timeout: 15).exists)
            shot("store-\(language)-05-share")
        }
        launch(["-demo", "-paywall"])
        XCTAssertTrue(wait("paywall.status").exists)
        shot("paid-01-paywall")
    }


    private func launch(_ flags: [String] = [], language: String = "en") {
        if app.state != .notRunning { app.terminate() }
        let locale = language == "zh-Hans" ? "zh_CN" : language == "zh-Hant" ? "zh_TW" : "en_US"
        app.launchArguments = ["-ui-testing", "-reset", "-today", "2026-11-24", "-AppleLanguages", "(\(language))", "-AppleLocale", locale] + flags
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func wait(_ id: String, timeout: TimeInterval = 8, slide: Bool = false, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let item = element(id)
        _ = item.waitForExistence(timeout: slide ? min(timeout, 3) : timeout)
        if slide {
            for _ in 0..<5 {
                if item.exists && item.isHittable { break }
                app.swipeUp()
                Thread.sleep(forTimeInterval: 1.2)
            }
        }
        XCTAssertTrue(item.exists, id, file: file, line: line)
        return item
    }

    private func tap(_ id: String, slide: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let item = wait(id, slide: slide, file: file, line: line)
        let ready = NSPredicate { _, _ in item.exists && item.isHittable && item.isEnabled }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 8), .completed, id, file: file, line: line)
        item.tap()
    }

    private func tapAlertConfirm() {
        let buttons = app.alerts.buttons.allElementsBoundByIndex
        let target = buttons.first { !["Cancel", "取消"].contains($0.label) } ?? buttons.last
        target?.tap()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
