import Foundation

/// Answer grades, matching FSRS's four ratings.
enum Grade: Int, CaseIterable, Codable, Sendable {
    case again = 1, hard = 2, good = 3, easy = 4

    var label: String {
        switch self {
        case .again: return "Forgot"
        case .hard: return "Hard"
        case .good: return "Got it"
        case .easy: return "Easy"
        }
    }
}

/// FSRS-5 scheduler (the open algorithm used by Anki), working in whole study days.
/// Reference: https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm
struct FSRS: Sendable {
    var w: [Double] = [0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0234, 1.616, 0.1544, 1.0824,
                       1.9813, 0.0953, 0.2975, 2.2042, 0.2407, 2.9466, 0.5034, 0.6567]
    var requestRetention: Double = 0.9
    var maximumInterval: Int = 3650

    static let decay = -0.5
    static let factor = pow(0.9, 1 / decay) - 1   // = 19/81, so R(S, S) = 0.9

    func retrievability(elapsedDays t: Double, stability s: Double) -> Double {
        pow(1 + FSRS.factor * t / max(s, 0.01), FSRS.decay)
    }

    func interval(for stability: Double) -> Int {
        let raw = stability / FSRS.factor * (pow(requestRetention, 1 / FSRS.decay) - 1)
        return min(max(Int(raw.rounded()), 1), maximumInterval)
    }

    private func initialStability(_ g: Grade) -> Double { max(w[g.rawValue - 1], 0.1) }

    private func initialDifficulty(_ g: Grade) -> Double {
        clampD(w[4] - exp(w[5] * Double(g.rawValue - 1)) + 1)
    }

    private func clampD(_ d: Double) -> Double { min(max(d, 1), 10) }

    private func nextDifficulty(_ d: Double, _ g: Grade) -> Double {
        let delta = -w[6] * Double(g.rawValue - 3)
        let next = d + delta * (10 - d) / 9   // linear damping
        // mean reversion toward the "easy" initial difficulty
        return clampD(w[7] * initialDifficulty(.easy) + (1 - w[7]) * next)
    }

    private func recallStability(d: Double, s: Double, r: Double, g: Grade) -> Double {
        let hardPenalty = g == .hard ? w[15] : 1
        let easyBonus = g == .easy ? w[16] : 1
        return s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * hardPenalty * easyBonus)
    }

    private func forgetStability(d: Double, s: Double, r: Double) -> Double {
        let sf = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14])
        return min(sf, s)
    }

    /// A brand-new card after its first answer.
    func first(_ g: Grade, today: Int) -> CardState {
        let s = initialStability(g)
        let d = initialDifficulty(g)
        let ivl = g == .again ? 0 : interval(for: s)
        return CardState(stability: s, difficulty: d, due: today + ivl, lastReview: today, reps: 1,
                         lapses: g == .again ? 1 : 0, learned: today)
    }

    /// Schedule an existing card. A review on the same day it was already reviewed only nudges
    /// difficulty, so drilling a word several times in one session does not inflate its interval.
    func review(_ card: CardState, _ g: Grade, today: Int) -> CardState {
        var c = card
        let elapsed = Double(max(0, today - card.lastReview))
        let r = retrievability(elapsedDays: elapsed, stability: card.stability)
        c.difficulty = nextDifficulty(card.difficulty, g)
        if elapsed < 1 {
            // same-day repeat (short-term step)
            let shortTerm = card.stability * exp(w[17] * (Double(g.rawValue) - 3 + w[18]))
            if g == .again {
                c.stability = max(0.1, shortTerm)
                c.lapses += 1
                c.due = today
            } else {
                c.stability = g == .hard ? max(0.1, shortTerm) : max(card.stability, shortTerm)
                c.due = today + interval(for: c.stability)
            }
        } else if g == .again {
            c.stability = max(0.1, forgetStability(d: card.difficulty, s: card.stability, r: r))
            c.lapses += 1
            c.due = today
        } else {
            c.stability = recallStability(d: card.difficulty, s: card.stability, r: r, g: g)
            var ivl = interval(for: c.stability)
            if g == .hard { ivl = min(ivl, max(1, interval(for: card.stability))) }
            c.due = today + ivl
        }
        c.reps += 1
        c.lastReview = today
        c.mastered = false
        return c
    }

    /// Preview of the interval (days) each grade would give. Used for the button captions.
    func preview(_ card: CardState?, today: Int) -> [Grade: Int] {
        var out: [Grade: Int] = [:]
        for g in Grade.allCases {
            let next = card.map { review($0, g, today: today) } ?? first(g, today: today)
            out[g] = next.due - today
        }
        return out
    }

    static func describe(days: Int) -> String {
        switch days {
        case ..<1: return "today"
        case 1: return "1 day"
        case 2..<30: return "\(days) days"
        case 30..<365:
            let m = Int((Double(days) / 30).rounded())
            return m == 1 ? "1 month" : "\(m) months"
        default:
            let y = Double(days) / 365
            return String(format: y < 10 ? "%.1f yr" : "%.0f yr", y)
        }
    }
}
