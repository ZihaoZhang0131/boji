import Foundation
import BojiDomain

/// Owns two distinct containers. Demo data is memory-only; personal references are retained.
public actor WorkspaceSession {
    public let personal: LocalRepository
    private var demo: LocalRepository?
    private var demoDirectory: URL?
    private let clock: any AppClock

    public init(personal: LocalRepository, clock: any AppClock) { self.personal = personal; self.clock = clock }

    public func activeRepository() -> LocalRepository { demo ?? personal }

    public func enterDemo() async throws {
        guard demo == nil else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("boji-demo-" + UUID().uuidString)
        let repository = try await LocalRepository.open(at: directory, mode: .demo, inMemory: true)
        var meal = Meal(time: RecordTime(clock: clock)); meal.note = "演示：一碗米饭和蔬菜"
        let example = meal
        try await repository.commit(id: UUID()) { $0.meals = [example] }
        demoDirectory = directory; demo = repository
    }

    public func leaveDemo() {
        demo = nil
        if let directory = demoDirectory { try? FileManager.default.removeItem(at: directory) }
        demoDirectory = nil
    }
}
