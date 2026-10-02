import Foundation
import Testing
@testable import TradeMemo

@Suite("LineCalculator")
struct LineCalculatorTests {
    @Test func stopByPercent() throws {
        #expect(try LineCalculator.stopPrice(entry: 1_000, method: .percent(5)) == 950)
    }

    @Test func stopByAmount() throws {
        #expect(try LineCalculator.stopPrice(entry: 1_000, method: .amount(63)) == 937)
    }

    @Test func stopMustBeBelowEntry() {
        #expect(throws: DomainError.stopNotBelowEntry) {
            try LineCalculator.stopPrice(entry: 1_000, method: .price(1_000))
        }
        #expect(throws: DomainError.stopNotBelowEntry) {
            try LineCalculator.stopPrice(entry: 1_000, method: .amount(-10))
        }
    }

    @Test func takeProfitByPercent() throws {
        #expect(try LineCalculator.takeProfitPrice(entry: 1_000, stop: 950, method: .percent(10)) == 1_100)
    }

    @Test func takeProfitMustBeAboveEntry() {
        #expect(throws: DomainError.takeProfitNotAboveEntry) {
            try LineCalculator.takeProfitPrice(entry: 1_000, stop: 950, method: .price(1_000))
        }
    }

    @Test func riskRewardRatio() {
        #expect(LineCalculator.riskRewardRatio(entry: 1_000, stop: 950, takeProfit: 1_100) == 2)
        #expect(LineCalculator.riskRewardRatio(entry: 1_000, stop: 1_000, takeProfit: 1_100) == nil)
    }
}

@Suite("PositionSizer")
struct PositionSizerTests {
    private func input(
        entry: Decimal = 1_000, stop: Decimal = 950, unit: Int = 100,
        lots: [LotSnapshot] = [], otherCost: Decimal = 0
    ) -> SizingInput {
        SizingInput(
            capital: 1_000_000, riskPercent: 2,
            entryPrice: entry, stopPrice: stop, takeProfitPrice: entry + 100,
            unit: unit, sameSymbolLots: lots, otherSymbolsCost: otherCost
        )
    }

    @Test("100株単位では買えないが1株単位なら買える")
    func belowUnit() throws {
        // d = 300 → qR = 66
        let result = try PositionSizer.calculate(input(stop: 700))
        #expect(result.quantity == 0)
        #expect(result.zeroReason == .belowUnit(quantityInSingleShares: 66))
    }

    @Test("1株あたりの損失が損失枠を超える")
    func perShareLossExceedsBudget() throws {
        let result = try PositionSizer.calculate(input(entry: 50_000, stop: 25_000, unit: 1))
        #expect(result.quantity == 0)
        #expect(result.zeroReason == .perShareLossExceedsBudget)
    }

    @Test("買付余力がない（取得金額が資金を超えていても負にならない）")
    func noBuyingPower() throws {
        let result = try PositionSizer.calculate(input(otherCost: 1_200_000))
        #expect(result.buyingPower == 0)
        #expect(result.quantity == 0)
        #expect(result.zeroReason == .noBuyingPower)
    }

    @Test("損切りを取得価格より上に引き上げたロットは損失 0（枠に足し戻さない）")
    func raisedStopDoesNotAddBack() throws {
        let lot = LotSnapshot(quantity: 400, entryPrice: 1_000, stopPrice: 1_050)
        #expect(lot.lossAtStop == 0)
        let result = try PositionSizer.calculate(input(entry: 1_100, stop: 1_050, lots: [lot]))
        #expect(result.remainingLoss == 20_000)
    }

    @Test("株数は切り捨て（端数の株は出さない）")
    func floorsQuantity() throws {
        // L / d = 20,000 / 33 = 606.06… → 606
        let result = try PositionSizer.calculate(input(stop: 967, unit: 1))
        #expect(result.quantityByRisk == 606)
        #expect(result.lossAtStop <= 20_000)
    }

    @Test func invalidInputs() {
        #expect(throws: DomainError.stopNotBelowEntry) {
            try PositionSizer.calculate(input(stop: 1_000))
        }
        #expect(throws: DomainError.invalidUnit) {
            try PositionSizer.calculate(input(unit: 0))
        }
    }

    @Test func averageOfNoLotsIsNil() {
        #expect(PositionSizer.averageEntryPrice(of: []) == nil)
    }
}

@Suite("ExitJudge 境界値")
struct ExitJudgeBoundaryTests {
    // S = 1,020、T = 1,140、tol = 2
    @Test(arguments: [
        (Decimal(1_018), ExitJudgment.kept),       // S − tol ちょうど
        (Decimal(1_022), ExitJudgment.kept),       // S + tol ちょうど
        (Decimal(1_017), ExitJudgment.late),
        (Decimal(1_023), ExitJudgment.unplanned),
        (Decimal(1_139), ExitJudgment.unplanned),
        (Decimal(1_200), ExitJudgment.takeProfit),
    ])
    func boundaries(exitPrice: Decimal, expected: ExitJudgment) {
        let result = ExitJudge.judge(stop: 1_020, takeProfit: 1_140, exitPrice: exitPrice, quantity: 100, tolerance: 2)
        #expect(result.judgment == expected)
    }
}

@Suite("ReviewStats")
struct ReviewStatsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func lot(_ judgment: ExitJudgment, _ exitDate: Date, overshoot: Decimal = 0) -> ClosedLotSummary {
        ClosedLotSummary(symbolName: "テスト", lotIndex: 1, exitDate: exitDate,
                         judgment: judgment, overshootAmount: overshoot, reason: "")
    }

    @Test func summarizeByPeriod() {
        let now = date(2026, 10, 15)
        let lots = [
            lot(.kept, date(2026, 10, 1)),
            lot(.late, date(2026, 10, 5), overshoot: 1_600),
            lot(.takeProfit, date(2026, 10, 10)),
            lot(.late, date(2026, 8, 20), overshoot: 3_000),
            lot(.unplanned, date(2026, 8, 1)),
            lot(.kept, date(2026, 7, 31)),
        ]

        let month = ReviewStats.summarize(lots, period: .thisMonth, now: now, calendar: calendar)
        #expect(month.keptCount == 1)
        #expect(month.lateCount == 1)
        #expect(month.takeProfitCount == 1)
        #expect(month.unplannedCount == 0)
        #expect(month.complianceRate == Decimal(string: "0.5"))
        #expect(month.excessLoss == 1_600)

        let threeMonths = ReviewStats.summarize(lots, period: .lastThreeMonths, now: now, calendar: calendar)
        #expect(threeMonths.lateCount == 2)
        #expect(threeMonths.unplannedCount == 1)
        #expect(threeMonths.keptCount == 1) // 7/31 は範囲外（8/1 から）
        #expect(threeMonths.excessLoss == 4_600)
        #expect(threeMonths.lateLots.map(\.overshootAmount) == [1_600, 3_000])

        let all = ReviewStats.summarize(lots, period: .all, now: now, calendar: calendar)
        #expect(all.keptCount == 2)
    }

    @Test("守れた＋遅れたが 0 件なら遵守率は nil（「—」表示）")
    func complianceRateNilWhenNoStops() {
        let now = date(2026, 10, 15)
        let summary = ReviewStats.summarize([lot(.takeProfit, now)], period: .all, now: now, calendar: calendar)
        #expect(summary.complianceRate == nil)
    }
}
