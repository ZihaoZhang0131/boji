import AVFoundation
import UIKit

@MainActor protocol CameraDevice {
    var available: Bool { get }
    var authorization: AVAuthorizationStatus { get }
    func requestAccess() async -> Bool
}

@MainActor struct SystemCameraDevice: CameraDevice {
    var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    func requestAccess() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }
}

enum CameraAccessResult: Equatable {
    case authorized, unavailable, denied
    var message: String? {
        switch self {
        case .authorized: nil
        case .unavailable: "当前设备无法使用相机，可从相册选择或继续文字记录。"
        case .denied: "相机权限未开启。可在系统设置中开启，或从相册选择、继续文字记录。"
        }
    }
}

@MainActor enum CameraAccess {
    static func authorize(using device: any CameraDevice) async -> CameraAccessResult {
        guard device.available else { return .unavailable }
        switch device.authorization {
        case .authorized: return .authorized
        case .notDetermined: return await device.requestAccess() ? .authorized : .denied
        default: return .denied
        }
    }
}
