import Foundation
import BojiDomain
import BojiEstimation
import BojiPersistence

struct AppDependencies {
    let storageRoot: URL?
    let clock: any AppClock
    let estimation: any FoodEstimationService
    let files: any FileAccess
    let credentials: any ServiceCredentials
    let remote: any EstimationRemote

    static func production(storageRoot: URL? = nil) -> Self {
        let credentials = KeychainCredentials()
        return Self(storageRoot: storageRoot, clock: SystemClock(), estimation: UnconfiguredEstimationService(), files: LocalFileAccess(), credentials: credentials, remote: PersonalEstimationRemote(credentials: credentials))
    }
}
