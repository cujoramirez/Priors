//
//  VillageAppearanceTests.swift
//  Captures the village so the rendering can be inspected rather than assumed.
//

import XCTest

final class VillageAppearanceTests: XCTestCase {

    func testVillageRenders() {
        let app = XCUIApplication()
        app.launchArguments = ["-startPhase", "village"]
        app.launch()
        // Let the scene build and the camera settle.
        Thread.sleep(forTimeInterval: 4.0)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "village"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(app.state == .runningForeground)
    }
}
