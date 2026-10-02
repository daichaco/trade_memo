import Foundation

/// 決済の判定（SPEC 3.7）
enum ExitJudgment: String, CaseIterable, Codable {
    /// 損切りを守れた
    case kept
    /// 損切りが遅れた
    case late
    /// 利確
    case takeProfit
    /// 計画外（ライン到達前の手仕舞い）
    case unplanned
}

struct ExitJudgeResult: Equatable {
    var judgment: ExitJudgment
    /// はみ出した額。遅れた のときだけ正の値、それ以外は 0
    var overshootAmount: Decimal
}

/// 決済の自動判定（SPEC 3.7）
enum ExitJudge {
    /// - Parameters:
    ///   - stop: 決済時点の損切りライン S（引き上げ後の値）
    ///   - takeProfit: 利確ライン T
    ///   - exitPrice: 決済価格 X
    ///   - quantity: 決済株数
    ///   - tolerance: 「守れた」とみなす幅 tol（円）
    static func judge(
        stop: Decimal,
        takeProfit: Decimal,
        exitPrice: Decimal,
        quantity: Int,
        tolerance: Decimal
    ) -> ExitJudgeResult {
        let judgment: ExitJudgment
        if exitPrice >= takeProfit {
            judgment = .takeProfit
        } else if abs(exitPrice - stop) <= tolerance {
            judgment = .kept
        } else if exitPrice < stop - tolerance {
            judgment = .late
        } else {
            judgment = .unplanned
        }
        let overshoot = judgment == .late
            ? overshootAmount(stop: stop, exitPrice: exitPrice, quantity: quantity)
            : 0
        return ExitJudgeResult(judgment: judgment, overshootAmount: overshoot)
    }

    /// はみ出した額 (S − X) × 決済株数。X ≥ S なら 0。
    /// 判定を手動で「遅れた」に変えたときにも使う。
    static func overshootAmount(stop: Decimal, exitPrice: Decimal, quantity: Int) -> Decimal {
        max(0, stop - exitPrice) * Decimal(quantity)
    }
}
