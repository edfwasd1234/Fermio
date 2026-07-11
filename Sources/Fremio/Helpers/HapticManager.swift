import UIKit

/// A manager for handling iOS Haptic Feedback, integrated with UserDefaults settings.
@MainActor
class HapticManager {
    static let shared = HapticManager()
    
    private init() {
        // Register default value if not set
        if UserDefaults.standard.object(forKey: "hapticsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "hapticsEnabled")
        }
    }
    
    /// Checks if haptics are enabled in the App settings.
    var isEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "hapticsEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hapticsEnabled")
        }
    }
    
    /// Triggers an impact haptic (light, medium, heavy, soft, rigid)
    /// - Parameter style: The impact style.
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }
    
    /// Triggers a notification haptic (success, warning, error)
    /// - Parameter type: The notification feedback type.
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(type)
        }
    }
    
    /// Triggers a selection-change haptic
    func selection() {
        guard isEnabled else { return }
        DispatchQueue.main.async {
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        }
    }
}
