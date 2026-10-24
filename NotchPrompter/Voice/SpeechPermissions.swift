import AVFoundation
import Speech

/// Microphone + speech recognition permission, requested together the first time word tracking is used.
enum SpeechPermissions {
    static var isDenied: Bool {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()
        return mic == .denied || mic == .restricted || speech == .denied || speech == .restricted
    }

    static var isGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Shows the system prompts that haven't been answered yet. Returns true if both are granted.
    static func request() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
        return isGranted
    }
}
