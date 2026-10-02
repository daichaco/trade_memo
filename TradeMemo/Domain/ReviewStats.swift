import Foundation

/// 振り返りの集計対象になる決済済みロット
struct ClosedLotSummary: Equatable {
    var symbolName: String
    /// ロット番号（1回目, 2回目…）
    var lotIndex: Int
    var exitDate: Date
    /// 最終判定（手動修正後）
    var judgment: ExitJudgment
    /// はみ出した額（遅れた のときに集計する）
    var overshootAmount: Decimal
    /// 理由メモ
    var reason: String
}

/// 振り返りの期間（決済日で絞る）
enum ReviewPeriod: CaseIterable {
    /// 今月（暦月）
    case thisMonth
    /// 今月を含む直近3か月（暦月）
    case lastThreeMonths
    case all

    /// 期間の開始日。全期間は nil。
    func startDate(now: Date, calendar: Calendar) -> Date? {
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        switch self {
        case .thisMonth:
            return monthStart
        case .lastThreeMonths:
            return calendar.date(byAdding: .month, value: -2, to: monthStart)
        case .all:
            return nil
        }
    }
}

struct ReviewSummary: Equatable {
    var keptCount: Int
    var lateCount: Int
    var takeProfitCount: Int
    var unplannedCount: Int
    /// 損切り遵守率 守れた ÷ (守れた + 遅れた)。0〜1。分母 0 のときは nil（「—」表示）
    var complianceRate: Decimal?
    /// ルール違反で余計に失った額（遅れたロットのはみ出した額の合計）
    var excessLoss: Decimal
    /// 損切りが遅れた取引の一覧（決済日の新しい順）
    var lateLots: [ClosedLotSummary]
}

/// 振り返りの集計（SPEC 3.8）
enum ReviewStats {
    static func summarize(
        _ lots: [ClosedLotSummary],
        period: ReviewPeriod,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReviewSummary {
        let start = period.startDate(now: now, calendar: calendar)
        let inPeriod = lots.filter { lot in
            guard let start else { return true }
            return lot.exitDate >= start && lot.exitDate <= now
        }

        func count(_ judgment: ExitJudgment) -> Int {
            inPeriod.filter { $0.judgment == judgment }.count
        }
        let kept = count(.kept)
        let late = count(.late)
        let lateLots = inPeriod
            .filter { $0.judgment == .late }
            .sorted { $0.exitDate > $1.exitDate }

        return ReviewSummary(
            keptCount: kept,
            lateCount: late,
            takeProfitCount: count(.takeProfit),
            unplannedCount: count(.unplanned),
            complianceRate: kept + late == 0 ? nil : Decimal(kept) / Decimal(kept + late),
            excessLoss: lateLots.reduce(0) { $0 + $1.overshootAmount },
            lateLots: lateLots
        )
    }
}
