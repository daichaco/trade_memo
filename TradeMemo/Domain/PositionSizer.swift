import Foundation

/// 保有中のロット（計算に必要な値だけ）
struct LotSnapshot: Equatable {
    var quantity: Int
    var entryPrice: Decimal
    /// 現在の損切りライン（引き上げ後の値）
    var stopPrice: Decimal

    /// 取得金額 q × e
    var cost: Decimal { Decimal(quantity) * entryPrice }

    /// 損切りされた場合の損失 max(0, e − s) × q（SPEC 3.5）。
    /// 損切りを取得価格以上に引き上げたロットは 0（利益分を枠に足し戻さない）。
    var lossAtStop: Decimal { max(0, entryPrice - stopPrice) * Decimal(quantity) }
}

/// 株数計算の入力（SPEC 3.4）
struct SizingInput: Equatable {
    /// 総資金 C
    var capital: Decimal
    /// 1回の許容損失率 r（2% なら 2）
    var riskPercent: Decimal
    /// 取得（予定）価格 E
    var entryPrice: Decimal
    /// 損切り価格 S
    var stopPrice: Decimal
    /// 利確価格 T
    var takeProfitPrice: Decimal
    /// 株数の単位 u（100 または 1）
    var unit: Int
    /// 同じ銘柄の保有中ロット（損失枠と買付余力の両方に影響）
    var sameSymbolLots: [LotSnapshot] = []
    /// 他の銘柄の保有中ロットの取得金額の合計（買付余力にだけ影響）
    var otherSymbolsCost: Decimal = 0
}

/// 株数が 0 になった理由（SPEC 3.4 の 9、例4）
enum ZeroQuantityReason: Equatable {
    /// 損失枠が残っていない（L ≤ 0）
    case noRiskBudgetLeft
    /// 買付余力が 1株分もない
    case noBuyingPower
    /// 1株あたりの損失が損失枠より大きく、1株も買えない
    case perShareLossExceedsBudget
    /// 単位未満になる。1株単位なら quantityInSingleShares 株買える
    case belowUnit(quantityInSingleShares: Int)
}

/// 株数計算の結果
struct SizingResult: Equatable {
    /// 1回の許容損失額 R
    var riskAllowance: Decimal
    /// 1株あたりの損失 d
    var perShareLoss: Decimal
    /// 同じ銘柄の既存ロットで使用中の損失
    var usedLoss: Decimal
    /// 損失枠 L（0 未満にはしない）
    var remainingLoss: Decimal
    /// 損失から出る株数 qR
    var quantityByRisk: Int
    /// 買付余力 B（0 未満にはしない）
    var buyingPower: Decimal
    /// 資金から出る株数 qB
    var quantityByCapital: Int
    /// 株数 q
    var quantity: Int

    /// 必要資金 q × E
    var requiredCapital: Decimal
    /// 損切り時の損失 q × d（正の値）
    var lossAtStop: Decimal
    /// 利確時の利益 q × (T − E)
    var profitAtTakeProfit: Decimal
    /// 資金に対するリスク率（%）lossAtStop / C × 100
    var riskPercentOfCapital: Decimal

    /// qB < qR：買付余力で上限に達している（警告を出す。実際のリスクは lossAtStop）
    var isLimitedByBuyingPower: Bool { quantityByCapital < quantityByRisk }
    /// q = 0 のときの理由
    var zeroReason: ZeroQuantityReason?
}

/// 株数の計算（SPEC 3.4, 3.5）
enum PositionSizer {
    static func calculate(_ input: SizingInput) throws -> SizingResult {
        let c = input.capital
        let e = input.entryPrice
        let s = input.stopPrice
        let t = input.takeProfitPrice
        let u = input.unit
        guard c > 0 else { throw DomainError.invalidCapital }
        guard input.riskPercent > 0 else { throw DomainError.invalidRiskPercent }
        guard e > 0 else { throw DomainError.invalidEntryPrice }
        guard s < e else { throw DomainError.stopNotBelowEntry }
        guard t > e else { throw DomainError.takeProfitNotAboveEntry }
        guard u >= 1 else { throw DomainError.invalidUnit }

        let r = c * input.riskPercent / 100
        // 1. 1株あたりの損失
        let d = e - s
        // 2. 損失枠
        let used = usedLoss(of: input.sameSymbolLots)
        let l = max(0, r - used)
        // 3. 損失から出る株数
        let qR = (l / d).flooredNonNegativeInt
        // 4. 買付余力（全銘柄の保有中ロットの取得金額を引く）
        let invested = input.otherSymbolsCost + input.sameSymbolLots.reduce(0) { $0 + $1.cost }
        let b = max(0, c - invested)
        // 5. 資金から出る株数
        let qB = (b / e).flooredNonNegativeInt
        // 6. 単位で切り捨て
        let single = min(qR, qB)
        let q = single / u * u

        let qty = Decimal(q)
        let loss = qty * d

        var zeroReason: ZeroQuantityReason?
        if q == 0 {
            if l <= 0 {
                zeroReason = .noRiskBudgetLeft
            } else if qB == 0 {
                zeroReason = .noBuyingPower
            } else if qR == 0 {
                zeroReason = .perShareLossExceedsBudget
            } else {
                zeroReason = .belowUnit(quantityInSingleShares: single)
            }
        }

        return SizingResult(
            riskAllowance: r,
            perShareLoss: d,
            usedLoss: used,
            remainingLoss: l,
            quantityByRisk: qR,
            buyingPower: b,
            quantityByCapital: qB,
            quantity: q,
            requiredCapital: qty * e,
            lossAtStop: loss,
            profitAtTakeProfit: qty * (t - e),
            riskPercentOfCapital: loss / c * 100,
            zeroReason: zeroReason
        )
    }

    /// 同じ銘柄の保有中ロットで使用中の損失（SPEC 3.5）
    static func usedLoss(of lots: [LotSnapshot]) -> Decimal {
        lots.reduce(0) { $0 + $1.lossAtStop }
    }

    /// 平均取得単価 Σ(q_i × e_i) / Σq_i。株数の合計が 0 のときは nil。
    static func averageEntryPrice(of lots: [LotSnapshot]) -> Decimal? {
        let totalQuantity = lots.reduce(0) { $0 + $1.quantity }
        guard totalQuantity > 0 else { return nil }
        let totalCost = lots.reduce(Decimal(0)) { $0 + $1.cost }
        return totalCost / Decimal(totalQuantity)
    }
}
