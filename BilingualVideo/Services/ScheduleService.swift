import Foundation

struct ScheduleService {
    var calendar: Calendar

    init(calendar: Calendar = .bilingualVideo) {
        self.calendar = calendar
    }

    func day(containing date: Date) -> LocalDay {
        LocalDay(date: date, calendar: calendar)
    }

    func generate(pairs: [VideoPair], startDate: Date, now: Date = Date()) -> ViewingPlan {
        ViewingPlan(
            startDay: day(containing: startDate),
            orderedPairIDs: pairs.sorted { $0.id < $1.id }.map(\.id),
            updatedAt: now
        )
    }

    func pairID(in plan: ViewingPlan, on date: Date) -> Int? {
        let targetDay = day(containing: date)
        guard let startDate = plan.startDay.date(in: calendar),
              let targetDate = targetDay.date(in: calendar) else {
            return nil
        }
        let offset = calendar.dateComponents([.day], from: startDate, to: targetDate).day
        guard let offset, plan.orderedPairIDs.indices.contains(offset) else {
            return nil
        }
        return plan.orderedPairIDs[offset]
    }

    func preview(_ plan: ViewingPlan) -> [ScheduledPair] {
        plan.orderedPairIDs.enumerated().compactMap { index, pairID in
            guard let day = plan.startDay.adding(days: index, calendar: calendar) else {
                return nil
            }
            return ScheduledPair(index: index, pairID: pairID, day: day)
        }
    }

    func shifting(_ plan: ViewingPlan, byDays days: Int) -> ViewingPlan {
        guard let shiftedStart = plan.startDay.adding(days: days, calendar: calendar) else {
            return plan
        }
        var copy = plan
        copy.startDay = shiftedStart
        return copy
    }

    func shifting(_ plan: ViewingPlan, movingPairID pairID: Int, to targetDay: LocalDay) -> ViewingPlan {
        guard let index = plan.orderedPairIDs.firstIndex(of: pairID),
              let newStart = targetDay.adding(days: -index, calendar: calendar) else {
            return plan
        }
        var copy = plan
        copy.startDay = newStart
        return copy
    }

    func dayDifference(from first: LocalDay, to second: LocalDay) -> Int? {
        guard let firstDate = first.date(in: calendar), let secondDate = second.date(in: calendar) else {
            return nil
        }
        return calendar.dateComponents([.day], from: firstDate, to: secondDate).day
    }
}

extension Calendar {
    static var bilingualVideo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }
}
