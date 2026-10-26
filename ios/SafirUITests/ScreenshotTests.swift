import XCTest

/// Design review without a phone: launches the app in screenshot mode (made-up chats, no server)
/// and saves screenshots of the main screens, light and dark. CI exports them as an artifact.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SafirScreenshots"] + extra
        app.launch()
        sleep(2)
        return app
    }

    private func walkthrough(dark: Bool) {
        let suffix = dark ? "dark" : "light"
        let app = launch(dark ? ["-SafirDark"] : [])
        shot(app, "1-chats-\(suffix)")

        app.staticTexts["Амина Саидова"].firstMatch.tap()
        sleep(2)
        shot(app, "2-chat-\(suffix)")
        app.buttons["chat-header"].firstMatch.tap()
        sleep(2)
        shot(app, "2b-profile-\(suffix)")
        app.buttons["profile-back"].firstMatch.tap()
        sleep(1)

        app.buttons["back"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Мактаби №1 — учителя"].firstMatch.tap()
        sleep(2)
        shot(app, "3-group-\(suffix)")
        app.buttons["chat-header"].firstMatch.tap()
        sleep(2)
        shot(app, "3b-group-profile-\(suffix)")
        app.swipeUp()
        sleep(1)
        shot(app, "3c-group-members-\(suffix)")
        app.buttons["profile-back"].firstMatch.tap()
        sleep(1)

        app.buttons["back"].firstMatch.tap()
        sleep(1)
        // Custom floating tab bar (UI/MainTabs.swift): tabs are found by id "tab-<index>".
        app.buttons["tab-1"].firstMatch.tap()
        sleep(1)
        shot(app, "4-contacts-\(suffix)")
        app.buttons["tab-2"].firstMatch.tap()
        sleep(1)
        shot(app, "5-calls-\(suffix)")
        app.buttons["tab-3"].firstMatch.tap()
        sleep(2)
        shot(app, "6-services-\(suffix)")
        // Each service screen, then back (navigation bar back button).
        for (id, name) in [("service-weather", "6a-weather"), ("service-currency", "6b-currency"),
                           ("service-news", "6c-news"), ("service-ai", "6d-ai")] {
            app.buttons[id].firstMatch.tap()
            sleep(2)
            if id == "service-ai" {
                let idea = app.staticTexts["План дня"].firstMatch
                if idea.waitForExistence(timeout: 2) {
                    idea.tap()
                    sleep(3)
                }
            }
            shot(app, "\(name)-\(suffix)")
            // A screen that did not open must not stop the remaining screenshots.
            let bar = app.navigationBars.firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 3), "\(id) did not open its screen")
            if bar.exists {
                bar.buttons.element(boundBy: 0).tap()
                sleep(1)
            }
        }
        app.buttons["tab-4"].firstMatch.tap()
        sleep(1)
        shot(app, "7-settings-\(suffix)")
        // Each settings page, then back (navigation bar back button).
        for (title, name) in [("Уведомления и звуки", "7a-notifications"), ("Конфиденциальность", "7b-privacy"),
                              ("Данные и память", "7c-data"), ("Оформление", "7d-appearance"), ("Устройства", "7e-devices"),
                              ("Избранное", "7g-saved"), ("Язык", "7h-language"), ("Safir Premium", "7i-premium"),
                              ("Мои боты", "7j-bots")] {
            let row = app.staticTexts[title].firstMatch
            guard row.waitForExistence(timeout: 2) else { continue }
            row.tap()
            sleep(2)
            shot(app, "\(name)-\(suffix)")
            let bar = app.navigationBars.firstMatch
            if bar.waitForExistence(timeout: 2) {
                bar.buttons.element(boundBy: 0).tap()
                sleep(1)
            }
        }
        app.buttons["settings-edit"].firstMatch.tap()
        sleep(2)
        shot(app, "7f-edit-profile-\(suffix)")
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        sleep(1)

        app.buttons["tab-0"].firstMatch.tap()
        sleep(1)
        app.buttons["new-chat"].firstMatch.tap()
        sleep(2)
        shot(app, "8-new-message-\(suffix)")
        app.staticTexts["Создать группу"].firstMatch.tap()
        sleep(1)
        app.staticTexts["Амина Саидова"].firstMatch.tap()
        app.staticTexts["Фарход Назаров"].firstMatch.tap()
        sleep(1)
        shot(app, "9-new-group-\(suffix)")
        app.terminate()
    }

    func testLight() { walkthrough(dark: false) }

    func testDark() { walkthrough(dark: true) }

    func testCall() {
        let incoming = launch(["-SafirDemoCall", "incoming"])
        _ = incoming.buttons["Принять"].waitForExistence(timeout: 8)
        shot(incoming, "10-call-incoming")
        incoming.terminate()
        let active = launch(["-SafirDemoCall", "active"])
        _ = active.buttons["Завершить"].waitForExistence(timeout: 8)
        shot(active, "11-call-active")
        active.terminate()
    }

    func testLogin() {
        let app = launch(["-SafirLoggedOut"])
        shot(app, "0-login-light")
        app.terminate()
        let dark = launch(["-SafirLoggedOut", "-SafirDark"])
        shot(dark, "0-login-dark")
        dark.terminate()
    }
}
