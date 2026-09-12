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
        pairIDs(in: plan, on: date, dailyGroupCount: 1).first
    }

    func pairIDs(in plan: ViewingPlan, on date: Date, dailyGroupCount: Int) -> [Int] {
        let targetDay = day(containing: date)
        let offset: Int?
        if let days = plan.scheduledDays {
            offset = days.firstIndex(of: targetDay)
        } else {
            offset = dayDifference(from: plan.startDay, to: targetDay)
        }
        guard dailyGroupCount > 0, let offset, plan.orderedPairIDs.indices.contains(offset) else {
            return []
        }
        return Array(plan.orderedPairIDs.dropFirst(offset).prefix(dailyGroupCount))
    }

    func scheduledDays(in plan: ViewingPlan) -> [LocalDay] {
        plan.scheduledDays ?? plan.orderedPairIDs.indices.compactMap {
            plan.startDay.adding(days: $0, calendar: calendar)
        }
    }

    func preview(_ plan: ViewingPlan) -> [ScheduledPair] {
        zip(plan.orderedPairIDs, scheduledDays(in: plan)).enumerated().map { index, entry in
            ScheduledPair(index: index, pairID: entry.0, day: entry.1)
        }
    }

    /// Settle only finished calendar days. A missing checkpoint is a legacy
    /// plan: start tracking today without inferring anything about earlier days.
    func settlingUnplayedDays(in plan: ViewingPlan, at date: Date) -> ViewingPlan {
        let today = day(containing: date)
        var copy = plan
        guard let tracking = plan.playbackTracking else {
            copy.playbackTracking = PlanPlaybackTracking(day: today, hasPlayed: false)
            return copy
        }
        guard tracking.day < today else { return copy }
        let firstUnplayedDay = tracking.hasPlayed
            ? tracking.day.adding(days: 1, calendar: calendar) ?? today
            : tracking.day
        var days = scheduledDays(in: plan)
        if let index = days.firstIndex(where: { $0 >= firstUnplayedDay && $0 < today }),
           let delay = dayDifference(from: days[index], to: today) {
            let shifted = days[index...].compactMap { $0.adding(days: delay, calendar: calendar) }
            guard shifted.count == days.count - index else { return copy }
            days.replaceSubrange(index..., with: shifted)
            copy.scheduledDays = days
            copy.startDay = days[0]
            copy.updatedAt = date
        }
        copy.playbackTracking = PlanPlaybackTracking(day: today, hasPlayed: false)
        return copy
    }

    func shifting(_ plan: ViewingPlan, byDays days: Int) -> ViewingPlan {
        guard let shiftedStart = plan.startDay.adding(days: days, calendar: calendar) else {
            return plan
        }
        var copy = plan
        copy.startDay = shiftedStart
        if let scheduledDays = plan.scheduledDays {
            let shifted = scheduledDays.compactMap { $0.adding(days: days, calendar: calendar) }
            guard shifted.count == scheduledDays.count else { return plan }
            copy.scheduledDays = shifted
        }
        return copy
    }

    func shifting(_ plan: ViewingPlan, movingPairID pairID: Int, to targetDay: LocalDay) -> ViewingPlan {
        let days = scheduledDays(in: plan)
        guard let index = plan.orderedPairIDs.firstIndex(of: pairID),
              days.indices.contains(index),
              let difference = dayDifference(from: days[index], to: targetDay) else {
            return plan
        }
        return shifting(plan, byDays: difference)
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
