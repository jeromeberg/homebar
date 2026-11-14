import Foundation
import HomeBarCore

extension HAEntity {
    var updateHelp: String {
        lastUpdated.map {
            "Updated: \($0.formatted(date: .abbreviated, time: .standard))"
        } ?? "Update time unavailable"
    }
}
