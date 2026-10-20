import Foundation
import BojiDomain

extension LocalRepository {
    public func confirmDay(_ day: LocalDay, confirmed: Bool, at now: Date, operationID: UUID) throws {
        try commit(id: operationID) { state in
            if confirmed && !state.activeMeals.contains(where: { $0.time.localDay == day }) { throw DomainError.invalidValue("请先记录至少一餐，空白日期不能作为零摄入确认") }
            state.confirmations.removeAll { $0.day == day }
            if confirmed { state.confirmations.append(DayConfirmation(day: day, confirmedAt: now, factsRevision: state.dataset.revision + 1)) }
        }
    }
}
