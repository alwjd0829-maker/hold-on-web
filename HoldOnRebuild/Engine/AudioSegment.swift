import Foundation

struct AudioSegment: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let startDate: Date
    var endDate: Date
}
