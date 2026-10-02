import Foundation

/// 計算の前提条件を満たさないときのエラー。画面側でメッセージに変換して表示する。
enum DomainError: Error, Equatable {
    /// 取得価格が 0 以下
    case invalidEntryPrice
    /// 損切り価格が取得価格以上（S < E を満たさない）
    case stopNotBelowEntry
    /// 利確価格が取得価格以下（T > E を満たさない）
    case takeProfitNotAboveEntry
    /// 総資金が 0 以下
    case invalidCapital
    /// 許容損失率が 0 以下
    case invalidRiskPercent
    /// 株数の単位が 1 未満
    case invalidUnit
}

extension Decimal {
    /// 小数点以下を切り捨てて Int にする（負の値は 0 とする）。
    /// 株数の計算は常に切り捨て。切り上げると許容損失を超えるため。
    var flooredNonNegativeInt: Int {
        guard self > 0 else { return 0 }
        var value = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
