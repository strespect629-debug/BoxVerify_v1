import Foundation

struct ScanStatsFinalSummary: Identifiable {

    let id: UUID = UUID()

    let types: Int
    let total: Int
    let top: [(String, Int)]

    static func from(session: ScanStatsSession) -> ScanStatsFinalSummary {

        let total = session.totalScans
        let types = session.codeCounts.count

        let top = session.codeCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }

        return ScanStatsFinalSummary(
            types: types,
            total: total,
            top: top
        )
    }
}
