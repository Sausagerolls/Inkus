import Foundation
import FoundationModels

enum AIAvailability {
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Human-readable reason when AI is unavailable. Returns nil when available.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "Apple Intelligence isn't available on this device."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to enable smart prompts."
            case .modelNotReady:
                return "Apple Intelligence is still downloading."
            @unknown default:
                return "Smart prompts aren't available right now."
            }
        }
    }
}
