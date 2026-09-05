import XCTest
@testable import BilingualVideo

final class ScheduleServiceTests: XCTestCase {
    func testLookupHasBoundariesAndNeverLoops() {
        let calendar = testCalendar()
        let service = ScheduleService(calendar: calendar)
        let plan = ViewingPlan(
            startDay: LocalDay(year: 2026, month: 9, day: 4),
            orderedPairIDs: [5, 20, 100],
            updatedAt: .distantPast
        )

        XCTAssertNil(service.pairID(in: plan, on: testDate(2026, 9, 3, calendar: calendar)))
        XCTAssertEqual(service.pairID(in: plan, on: testDate(2026, 9, 4, hour: 23, calendar: calendar)), 5)
        XCTAssertEqual(service.pairID(in: plan, on: testDate(2026, 9, 6, calendar: calendar)), 100)
        XCTAssertNil(service.pairID(in: plan, on: testDate(2026, 9, 7, calendar: calendar)))
    }

    func testLookupAcrossDaylightSavingUsesCalendarDays() {
        let calendar = testCalendar(timeZoneIdentifier: "America/Los_Angeles")
        let service = ScheduleService(calendar: calendar)
        let plan = ViewingPlan(
            startDay: LocalDay(year: 2026, month: 3, day: 7),
            orderedPairIDs: [1, 2, 3],
            updatedAt: .distantPast
        )

        XCTAssertEqual(service.pairID(in: plan, on: testDate(2026, 3, 8, calendar: calendar)), 2)
        XCTAssertEqual(service.pairID(in: plan, on: testDate(2026, 3, 9, calendar: calendar)), 3)
    }

    func testDraggingMiddlePairShiftsWholePlanWithoutReordering() {
        let calendar = testCalendar()
        let service = ScheduleService(calendar: calendar)
        let plan = ViewingPlan(
            startDay: LocalDay(year: 2026, month: 9, day: 4),
            orderedPairIDs: [5, 20, 100],
            updatedAt: .distantPast
        )

        let shifted = service.shifting(
            plan,
            movingPairID: 20,
            to: LocalDay(year: 2026, month: 9, day: 12)
        )

        XCTAssertEqual(shifted.startDay, LocalDay(year: 2026, month: 9, day: 11))
        XCTAssertEqual(shifted.orderedPairIDs, plan.orderedPairIDs)
        XCTAssertEqual(service.preview(shifted).map(\.day), [
            LocalDay(year: 2026, month: 9, day: 11),
            LocalDay(year: 2026, month: 9, day: 12),
            LocalDay(year: 2026, month: 9, day: 13)
        ])
    }

    func testShiftCrossesLeapDayAndPreservesOrder() {
        let calendar = testCalendar()
        let service = ScheduleService(calendar: calendar)
        let plan = ViewingPlan(
            startDay: LocalDay(year: 2028, month: 2, day: 28),
            orderedPairIDs: [100, 5, 20],
            updatedAt: .distantPast
        )

        let shifted = service.shifting(plan, byDays: 2)

        XCTAssertEqual(shifted.startDay, LocalDay(year: 2028, month: 3, day: 1))
        XCTAssertEqual(shifted.orderedPairIDs, [100, 5, 20])
    }

    func testNegativeSameDayAndUnknownPairShifts() {
        let calendar = testCalendar()
        let service = ScheduleService(calendar: calendar)
        let plan = ViewingPlan(
            startDay: LocalDay(year: 2026, month: 9, day: 4),
            orderedPairIDs: [5, 20, 100],
            updatedAt: .distantPast
        )

        XCTAssertEqual(
            service.shifting(plan, byDays: -5).startDay,
            LocalDay(year: 2026, month: 8, day: 30)
        )
        XCTAssertEqual(service.shifting(plan, byDays: 0), plan)
        XCTAssertEqual(
            service.shifting(
                plan,
                movingPairID: 20,
                to: LocalDay(year: 2026, month: 8, day: 29)
            ).startDay,
            LocalDay(year: 2026, month: 8, day: 28)
        )
        XCTAssertEqual(
            service.shifting(
                plan,
                movingPairID: 20,
                to: LocalDay(year: 2026, month: 8, day: 29)
            ).orderedPairIDs,
            plan.orderedPairIDs
        )
        XCTAssertEqual(
            service.shifting(
                plan,
                movingPairID: 999,
                to: LocalDay(year: 2026, month: 10, day: 1)
            ),
            plan
        )
    }

    func testGenerationAlwaysUsesNumericPairOrder() {
        let calendar = testCalendar()
        let service = ScheduleService(calendar: calendar)
        let pairs = [
            VideoPair(id: 100, chineseFileName: "100.mp4", englishFileName: "100.mp4"),
            VideoPair(id: 5, chineseFileName: "005.mp4", englishFileName: "5.mp4"),
            VideoPair(id: 20, chineseFileName: "20.mp4", englishFileName: "020.mp4")
        ]

        let plan = service.generate(
            pairs: pairs,
            startDate: testDate(2026, 9, 4, hour: 21, calendar: calendar),
            now: .distantPast
        )

        XCTAssertEqual(plan.startDay, LocalDay(year: 2026, month: 9, day: 4))
        XCTAssertEqual(plan.orderedPairIDs, [5, 20, 100])
    }
}
