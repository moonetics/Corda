import Foundation
import UserNotifications
import AppKit

/// Manages interactive macOS notifications for incoming OTP codes and device battery alerts.
public final class OtpNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = OtpNotificationManager()

    public static let categoryOtp = "CORDA_OTP_CATEGORY"
    public static let actionCopyCode = "CORDA_COPY_CODE_ACTION"

    private var lastAlertedBatteryLevel: Int? = nil
    private var lastAlertedChargingState: Bool? = nil
    private var otpClearTimer: Timer? = nil

    private override init() {
        super.init()
    }

    /// Register notification categories and delegate
    public func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let copyAction = UNNotificationAction(
            identifier: Self.actionCopyCode,
            title: "Salin Kode",
            options: [.foreground]
        )

        let otpCategory = UNNotificationCategory(
            identifier: Self.categoryOtp,
            actions: [copyAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([otpCategory])

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            #if DEBUG
            if let error = error {
                print("[OtpNotification] Notification authorization error: \(error)")
            } else {
                print("[OtpNotification] Notification authorization granted: \(granted)")
            }
            #endif
        }
    }

    /// Present an interactive notification for an incoming OTP code
    public func showOtpNotification(serviceName: String, code: String, expiresIn: Int) {
        // Auto-copy to pasteboard if enabled by user
        let autoCopyEnabled = UserDefaults.standard.bool(forKey: "otp_auto_copy")
        if autoCopyEnabled {
            copyToClipboard(code: code)
        }

        let content = UNMutableNotificationContent()
        content.title = "🔑 Kode OTP Terdeteksi (\(serviceName))"
        content.body = "\(code) (Kedaluwarsa dalam \(expiresIn) detik)"
        content.sound = .default
        content.categoryIdentifier = Self.categoryOtp
        content.userInfo = [
            "code": code,
            "service_name": serviceName,
            "expires_in": expiresIn
        ]

        let request = UNNotificationRequest(
            identifier: "otp_\(code)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("[OtpNotification] Failed to deliver OTP notification: \(error)")
            } else {
                print("[OtpNotification] Successfully posted OTP notification for \(serviceName)")
            }
            #endif
        }
    }

    /// Present a mirrored smartphone notification in macOS Notification Center.
    public func showNotificationMirror(
        notificationId: String,
        packageName: String,
        appName: String,
        title: String,
        text: String
    ) {
        let isEnabled = UserDefaults.standard.object(forKey: "notification_mirroring_enabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "notification_mirroring_enabled")
        guard isEnabled else { return }

        let hidePreview = UserDefaults.standard.bool(forKey: "notification_hide_preview")
        let displayBody = hidePreview ? "Pesan Baru Diterima" : text
        let displayTitle = title.isEmpty ? appName : "\(appName): \(title)"

        let content = UNMutableNotificationContent()
        content.title = displayTitle
        content.body = displayBody
        content.sound = .default
        content.userInfo = [
            "type": "NOTIFICATION_MIRROR",
            "package_name": packageName,
            "notification_id": notificationId
        ]

        let request = UNNotificationRequest(
            identifier: "mirror_\(packageName)_\(notificationId)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("[NotificationMirror] Failed to deliver mirrored notification: \(error)")
            } else {
                print("[NotificationMirror] Successfully posted mirrored notification for \(appName)")
            }
            #endif
        }
    }

    /// Check battery thresholds and trigger low/full charge alerts
    public func checkBatteryThresholds(level: Int, isCharging: Bool, deviceName: String = "Android") {
        // 1. Low battery alert (< 20% and not charging)
        if level <= 20 && !isCharging {
            if lastAlertedBatteryLevel == nil || (lastAlertedBatteryLevel! > 20) {
                lastAlertedBatteryLevel = level
                postLocalAlert(
                    title: "🪫 Baterai Lemah (\(level)%)",
                    body: "Baterai \(deviceName) tersisa \(level)%. Segera hubungkan ke pengisi daya."
                )
            }
        } else if isCharging && level == 100 {
            // 2. Full charge alert (100% and charging)
            if lastAlertedChargingState != true || (lastAlertedBatteryLevel ?? 0) < 100 {
                lastAlertedBatteryLevel = 100
                lastAlertedChargingState = true
                postLocalAlert(
                    title: "⚡ Baterai Terisi Penuh (100%)",
                    body: "Baterai \(deviceName) telah terisi 100%. Anda dapat mencabut pengisi daya."
                )
            }
        } else if !isCharging {
            lastAlertedChargingState = false
            if level > 25 {
                lastAlertedBatteryLevel = nil
            }
        }
    }

    private func postLocalAlert(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "battery_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// Copy code to NSPasteboard with optional auto-clear timer
    public func copyToClipboard(code: String) {
        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(code, forType: .string)

            #if DEBUG
            print("[OtpNotification] Code '\(code)' successfully copied to macOS pasteboard.")
            #endif

            // Reset any existing clear timer
            self.otpClearTimer?.invalidate()
            self.otpClearTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { _ in
                // Only clear if pasteboard still holds this specific code
                if pasteboard.string(forType: .string) == code {
                    pasteboard.clearContents()
                    #if DEBUG
                    print("[OtpNotification] Expired OTP '\(code)' cleared from macOS pasteboard.")
                    #endif
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even when app is active
        completionHandler([.banner, .sound, .badge])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let code = userInfo["code"] as? String {
            copyToClipboard(code: code)
        }
        completionHandler()
    }
}
