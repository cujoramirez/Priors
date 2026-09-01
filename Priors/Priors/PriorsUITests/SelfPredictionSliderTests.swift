//
//  SelfPredictionSliderTests.swift
//  Reproduction for the reported "slider does not trigger" behaviour.
//
//  The screen sits behind a full 30-decision session, so it is opened directly
//  with `-startPhase selfPrediction`.
//

import XCTest

final class SelfPredictionSliderTests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-startPhase", "selfPrediction"]
        app.launch()
        return app
    }

    /// The readout must exist and start at the documented midpoint.
    func testSliderStartsAtFiftyPercent() {
        let app = launch()
        let value = app.staticTexts["selfPredictionValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        XCTAssertEqual(value.label, "50%")
    }

    /// Dragging must move the value. This is the reported defect: if the slider
    /// only responds at an extreme, the intermediate positions fail here.
    func testDraggingChangesTheValue() {
        let app = launch()
        let slider = app.descendants(matching: .any)["selfPredictionSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        let value = app.staticTexts["selfPredictionValue"]

        // A press that starts mid-track, away from the thumb. SwiftUI's stock
        // Slider ignored this entirely — the reported defect.
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let quarter = value.label
        XCTAssertNotEqual(quarter, "50%", "tapping the track at 25% did nothing")

        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        XCTAssertNotEqual(value.label, quarter, "tapping the track at 80% did nothing")
    }

    /// Both ends must be reachable by dragging, which is what a player does.
    ///
    /// `adjust(toNormalizedSliderPosition:)` taps inside the element frame,
    /// but a slider maps its value across the track inset by half a thumb, so a
    /// tap at the frame edge lands a step short — it reported 99% at the top.
    /// A drag that continues past the end clamps, so this is the honest test of
    /// whether a player can actually say 0% or 100%.
    func testEndsAreReachableByDragging() {
        let app = launch()
        let slider = app.descendants(matching: .any)["selfPredictionSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        let value = app.staticTexts["selfPredictionValue"]

        let left = slider.coordinate(withNormalizedOffset: CGVector(dx: -0.2, dy: 0.5))
        let right = slider.coordinate(withNormalizedOffset: CGVector(dx: 1.2, dy: 0.5))
        let middle = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        middle.press(forDuration: 0.05, thenDragTo: left)
        XCTAssertEqual(value.label, "0%", "could not drag to the low end")

        middle.press(forDuration: 0.05, thenDragTo: right)
        XCTAssertEqual(value.label, "100%", "could not drag to the high end")
    }

    /// Every value the player can land on must be inside the range COPY R5
    /// interpolates. A slider that can report a negative percentage would put a
    /// number in the report that means nothing.
    func testValueNeverLeavesZeroToOneHundred() {
        let app = launch()
        let slider = app.descendants(matching: .any)["selfPredictionSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        let value = app.staticTexts["selfPredictionValue"]

        for dx in [-0.4, -0.1, 0.0, 0.5, 1.0, 1.4] {
            let target = slider.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
            slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: target)
            let shown = Int(value.label.replacingOccurrences(of: "%", with: "")) ?? -1
            XCTAssertTrue((0...100).contains(shown),
                          "slider reported \(shown)% at normalised \(dx)")
        }
    }
}
