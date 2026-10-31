import Testing
@testable import CodexBar

struct SpendDashboardSharesTests {
    private struct Row: Identifiable {
        let id: String
        let cost: Double?
        let tokens: Int?
    }

    @Test
    func `fully priced collections compare spend even when token shares differ`() {
        let rows = [Row(id: "a", cost: 10, tokens: 900), Row(id: "b", cost: 30, tokens: 100)]
        #expect(spendDashboardShares(rows, cost: \.cost, tokens: \.tokens) == ["a": 0.25, "b": 0.75])
    }

    @Test
    func `one unpriced row switches every bar to token shares`() {
        let rows = [Row(id: "a", cost: 10, tokens: 100), Row(id: "b", cost: nil, tokens: 900)]
        #expect(spendDashboardShares(rows, cost: \.cost, tokens: \.tokens) == ["a": 0.1, "b": 0.9])
    }

    @Test
    func `unpriced collections compare tokens`() {
        let rows = [Row(id: "a", cost: nil, tokens: 1), Row(id: "b", cost: nil, tokens: 3)]
        #expect(spendDashboardShares(rows, cost: \.cost, tokens: \.tokens) == ["a": 0.25, "b": 0.75])
    }

    @Test
    func `missing token counts do not establish a partial denominator`() {
        let rows = [Row(id: "a", cost: 10, tokens: nil), Row(id: "b", cost: nil, tokens: 900)]
        #expect(spendDashboardShares(rows, cost: \.cost, tokens: \.tokens).isEmpty)
    }

    @Test
    func `overflowing token totals hide shares without trapping`() {
        let rows = [Row(id: "a", cost: nil, tokens: .max), Row(id: "b", cost: nil, tokens: 1)]
        #expect(spendDashboardShares(rows, cost: \.cost, tokens: \.tokens).isEmpty)
    }

    @Test
    func `overflowing spend does not become a zero share or switch metrics`() {
        let rows = [
            Row(id: "a", cost: .greatestFiniteMagnitude, tokens: 1),
            Row(id: "b", cost: .greatestFiniteMagnitude, tokens: 3),
        ]
        #expect(spendDashboardShares(rows, cost: \.cost, tokens: \.tokens).isEmpty)
    }

    @Test
    func `zero totals and empty collections have no shares`() {
        for rows in [[], [Row(id: "a", cost: 0, tokens: 1)], [Row(id: "a", cost: nil, tokens: 0)]] {
            #expect(spendDashboardShares(rows, cost: \.cost, tokens: \.tokens).isEmpty)
        }
    }

    @Test
    func `largest valid token total remains finite`() {
        let rows = [Row(id: "a", cost: nil, tokens: Int.max - 1), Row(id: "b", cost: nil, tokens: 1)]
        let shares = spendDashboardShares(rows, cost: \.cost, tokens: \.tokens)
        #expect(shares.count == 2)
        #expect(shares.values.allSatisfy { $0.isFinite && (0...1).contains($0) })
        #expect(shares["b"] == 1 / Double(Int.max))
    }
}
