import Foundation

/// 損切りラインの決め方（SPEC 3.2）
enum StopMethod: Equatable {
    /// 取得価格から p% 下（5% なら 5 を渡す）
    case percent(Decimal)
    /// 取得価格から 1株あたり a 円下
    case amount(Decimal)
    /// 価格を直接指定
    case price(Decimal)
}

/// 利確ラインの決め方（SPEC 3.3）
enum TakeProfitMethod: Equatable {
    /// 取得価格から q% 上（10% なら 10 を渡す）
    case percent(Decimal)
    /// 価格を直接指定
    case price(Decimal)
    /// リスクリワード倍率 k（T = E + k × (E − S)）
    case riskReward(Decimal)
}

/// 損切り・利確ラインの計算（SPEC 3.2, 3.3）
enum LineCalculator {
    /// 損切り価格 S を求める。S < E を満たさなければエラー。
    static func stopPrice(entry: Decimal, method: StopMethod) throws -> Decimal {
        guard entry > 0 else { throw DomainError.invalidEntryPrice }
        let stop: Decimal
        switch method {
        case .percent(let p):
            stop = entry * (1 - p / 100)
        case .amount(let a):
            stop = entry - a
        case .price(let s):
            stop = s
        }
        guard stop < entry else { throw DomainError.stopNotBelowEntry }
        return stop
    }

    /// 利確価格 T を求める。T > E を満たさなければエラー。
    static func takeProfitPrice(entry: Decimal, stop: Decimal, method: TakeProfitMethod) throws -> Decimal {
        guard entry > 0 else { throw DomainError.invalidEntryPrice }
        let takeProfit: Decimal
        switch method {
        case .percent(let q):
            takeProfit = entry * (1 + q / 100)
        case .price(let t):
            takeProfit = t
        case .riskReward(let k):
            guard stop < entry else { throw DomainError.stopNotBelowEntry }
            takeProfit = entry + k * (entry - stop)
        }
        guard takeProfit > entry else { throw DomainError.takeProfitNotAboveEntry }
        return takeProfit
    }

    /// リスクリワード比 (T − E) / (E − S)。S ≥ E のときは nil。
    static func riskRewardRatio(entry: Decimal, stop: Decimal, takeProfit: Decimal) -> Decimal? {
        let risk = entry - stop
        guard risk > 0 else { return nil }
        return (takeProfit - entry) / risk
    }
}
