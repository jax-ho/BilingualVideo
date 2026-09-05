import XCTest
@testable import BilingualVideo

final class ScheduleStoreTests: XCTestCase {
    func testSaveLoadAndAtomicReplacement() throws {
        let environment = try TemporaryAppEnvironment()
        let store = ScheduleStore(
            fileURL: environment.directories.scheduleURL,
            fileManager: environment.directories.fileManager
        )
        let first = ViewingPlan(
            startDay: LocalDay(year: 2026, month: 9, day: 4),
            orderedPairIDs: [5, 20],
            updatedAt: testDate(2026, 9, 4)
        )
        let second = ViewingPlan(
            startDay: LocalDay(year: 2026, month: 9, day: 10),
            orderedPairIDs: [20, 5],
            updatedAt: testDate(2026, 9, 5)
        )

        try store.save(first)
        XCTAssertEqual(try store.load(), first)
        try store.save(second)
        XCTAssertEqual(try store.load(), second)

        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: environment.directories.applicationSupportURL.path
        ).filter { $0.hasPrefix(".schedule-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testCorruptPlanThrowsInsteadOfLookingLikeNoPlan() throws {
        let environment = try TemporaryAppEnvironment()
        let store = ScheduleStore(
            fileURL: environment.directories.scheduleURL,
            fileManager: environment.directories.fileManager
        )
        try Data("not json".utf8).write(to: environment.directories.scheduleURL)

        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: environment.directories.scheduleURL), Data("not json".utf8))
    }
}
