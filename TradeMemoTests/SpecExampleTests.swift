import Foundation
import Testing
@testable import TradeMemo

/// docs/SPEC.md 4章の計算例。
/// 共通設定：C = 1,000,000、r = 2%（R = 20,000）、u = 100
@Suite("SPEC 4章 計算例")
struct SpecExampleTests {
    let capital: Decimal = 1_000_000
    let riskPercent: Decimal = 2

    @Test("例1：新規")
    func example1() throws {
        let entry: Decimal = 1_000
        let stop: Decimal = 950
        let takeProfit = try LineCalculator.takeProfitPrice(entry: entry, stop: stop, method: .riskReward(2.0))
        #expect(takeProfit == 1_100)

        let result = try PositionSizer.calculate(SizingInput(
            capital: capital, riskPercent: riskPercent,
            entryPrice: entry, stopPrice: stop, takeProfitPrice: takeProfit,
            unit: 100, otherSymbolsCost: 300_000
        ))
        #expect(result.riskAllowance == 20_000)
        #expect(result.perShareLoss == 50)
        #expect(result.quantityByRisk == 400)
        #expect(result.buyingPower == 700_000)
        #expect(result.quantityByCapital == 700)
        #expect(result.quantity == 400)
        #expect(result.requiredCapital == 400_000)
        #expect(result.lossAtStop == 20_000)
        #expect(result.profitAtTakeProfit == 40_000)
        #expect(result.riskPercentOfCapital == 2)
        #expect(result.isLimitedByBuyingPower == false)
        #expect(result.zeroReason == nil)
    }

    @Test("例2：1株単位")
    func example2() throws {
        func sizing(unit: Int) throws -> SizingResult {
            try PositionSizer.calculate(SizingInput(
                capital: capital, riskPercent: riskPercent,
                entryPrice: 1_000, stopPrice: 937, takeProfitPrice: 1_126,
                unit: unit, otherSymbolsCost: 300_000
            ))
        }
        let single = try sizing(unit: 1)
        #expect(single.perShareLoss == 63)
        #expect(single.quantityByRisk == 317)
        #expect(single.quantity == 317)

        let hundred = try sizing(unit: 100)
        #expect(hundred.quantity == 300)
    }

    @Test("例3：買い増し（1回目の損切りを取得価格へ引き上げ済み）")
    func example3() throws {
        let firstLot = LotSnapshot(quantity: 400, entryPrice: 1_000, stopPrice: 1_000)
        let result = try PositionSizer.calculate(SizingInput(
            capital: capital, riskPercent: riskPercent,
            entryPrice: 1_060, stopPrice: 1_020, takeProfitPrice: 1_140,
            unit: 100, sameSymbolLots: [firstLot], otherSymbolsCost: 0
        ))
        #expect(result.usedLoss == 0)
        #expect(result.remainingLoss == 20_000)
        #expect(result.perShareLoss == 40)
        #expect(result.quantityByRisk == 500)
        #expect(result.buyingPower == 600_000)
        #expect(result.quantityByCapital == 566)
        #expect(result.quantity == 500)

        let newLot = LotSnapshot(quantity: result.quantity, entryPrice: 1_060, stopPrice: 1_020)
        let average = try #require(PositionSizer.averageEntryPrice(of: [firstLot, newLot]))
        // (400×1,000 + 500×1,060) / 900 = 1,033.33…
        #expect(rounded(average, scale: 2) == Decimal(string: "1033.33"))
    }

    @Test("例4：買い増しで枠が残っていない")
    func example4() throws {
        let firstLot = LotSnapshot(quantity: 400, entryPrice: 1_000, stopPrice: 950)
        let result = try PositionSizer.calculate(SizingInput(
            capital: capital, riskPercent: riskPercent,
            entryPrice: 1_060, stopPrice: 1_020, takeProfitPrice: 1_140,
            unit: 100, sameSymbolLots: [firstLot]
        ))
        #expect(result.usedLoss == 20_000)
        #expect(result.remainingLoss == 0)
        #expect(result.quantity == 0)
        #expect(result.zeroReason == .noRiskBudgetLeft)
    }

    @Test("例5：資金で頭打ち")
    func example5() throws {
        let result = try PositionSizer.calculate(SizingInput(
            capital: capital, riskPercent: riskPercent,
            entryPrice: 1_000, stopPrice: 950, takeProfitPrice: 1_100,
            unit: 100, otherSymbolsCost: 900_000
        ))
        #expect(result.quantityByRisk == 400)
        #expect(result.quantityByCapital == 100)
        #expect(result.quantity == 100)
        #expect(result.isLimitedByBuyingPower)
        #expect(result.lossAtStop == 5_000)
    }

    @Test("例6：決済判定（S = 1,020、T = 1,140、tol = 2、200株）", arguments: [
        (Decimal(1_019), ExitJudgment.kept, Decimal(0)),
        (Decimal(1_012), ExitJudgment.late, Decimal(1_600)),
        (Decimal(1_140), ExitJudgment.takeProfit, Decimal(0)),
        (Decimal(1_080), ExitJudgment.unplanned, Decimal(0)),
    ])
    func example6(exitPrice: Decimal, expected: ExitJudgment, overshoot: Decimal) {
        let result = ExitJudge.judge(stop: 1_020, takeProfit: 1_140, exitPrice: exitPrice, quantity: 200, tolerance: 2)
        #expect(result.judgment == expected)
        #expect(result.overshootAmount == overshoot)
    }

    private func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }
}
