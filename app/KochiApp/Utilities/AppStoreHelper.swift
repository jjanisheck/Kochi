import Foundation
import StoreKit
import AppKit

// MARK: - App Store Helper
class AppStoreHelper: ObservableObject {
    static let shared = AppStoreHelper()
    
    @Published var appVersion: String = "1.0.0"
    @Published var buildNumber: String = "1"
    @Published var hasRequestedReview = false
    @Published var launchCount = 0
    
    // App Store Connect Information
    let appStoreID = "YOUR_APP_STORE_ID" // Replace with actual ID
    let developerName = "Your Company Name"
    let supportEmail = "support@yourcompany.com"
    let privacyPolicyURL = "https://yourcompany.com/privacy"
    let termsOfServiceURL = "https://yourcompany.com/terms"
    
    init() {
        loadAppInfo()
        trackLaunch()
    }
    
    // MARK: - App Information
    private func loadAppInfo() {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            appVersion = version
        }
        
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            buildNumber = build
        }
        
        launchCount = UserDefaults.standard.integer(forKey: "LaunchCount")
        hasRequestedReview = UserDefaults.standard.bool(forKey: "HasRequestedReview")
    }
    
    private func trackLaunch() {
        launchCount += 1
        UserDefaults.standard.set(launchCount, forKey: "LaunchCount")
    }
    
    // MARK: - Review Request
    func requestReviewIfAppropriate() {
        // Request review after 5 launches and if not already requested
        guard launchCount >= 5, !hasRequestedReview else { return }

        hasRequestedReview = true
        UserDefaults.standard.set(true, forKey: "HasRequestedReview")
    }
    
    // MARK: - App Store Metadata
    func generateAppStoreMetadata() -> AppStoreMetadata {
        return AppStoreMetadata(
            appName: "Kochi - AI Presentation Coach",
            subtitle: "Transform Your Speaking Skills",
            keywords: [
                "presentation", "coach", "AI", "speech", "public speaking",
                "transcription", "feedback", "practice", "communication",
                "professional", "improvement", "training", "voice", "recording"
            ],
            description: appDescription,
            whatsNew: whatsNewText,
            categories: [.education, .productivity],
            screenshots: generateScreenshotDescriptions(),
            appPreviewVideoURL: nil
        )
    }
    
    private var appDescription: String {
        """
Transform your presentation skills with Kochi, your personal AI-powered speaking coach. Whether you're preparing for a big presentation, improving your communication skills, or overcoming public speaking anxiety, Kochi provides real-time feedback and personalized coaching to help you succeed.

**Key Features:**

🎙️ **Smart Recording & Transcription**
• Record presentations with crystal-clear audio quality
• Get instant, accurate transcriptions
• Support for multiple languages
• Offline transcription available

🧠 **AI-Powered Coaching**
• Real-time feedback on pace, clarity, and engagement
• Identify and reduce filler words
• Improve vocal variety and emphasis
• Personalized improvement suggestions

🎯 **Meeting Goals**
• Set specific meeting objectives
• Track goal achievement in real-time
• Get personalized coaching strategies
• Ensure productive conversations

📊 **Track Your Progress**
• Set and achieve speaking goals
• Detailed analytics and insights
• Progress tracking over time
• Export reports for review

🎨 **Beautiful & Intuitive**
• 8 stunning themes to choose from
• Smooth animations and transitions
• Accessibility-first design
• Dark mode support

🔒 **Privacy First**
• All processing happens on-device
• Your recordings stay private
• No data leaves your device
• Complete control over your content

**Perfect For:**
• Business professionals
• Students and educators
• Public speakers
• Job interview preparation
• Anyone wanting to improve communication

Start your journey to becoming a confident, compelling speaker with Kochi today!
"""
    }
    
    private var whatsNewText: String {
        """
Version \(appVersion) - Initial Release

🎉 Welcome to Kochi!

We're excited to introduce Kochi, your new AI-powered presentation coach:

• Record and transcribe presentations instantly
• Get real-time AI coaching feedback
• Analyze speaking patterns and clarity
• Track your speaking progress
• Choose from 8 beautiful themes
• All processing happens on-device for privacy

We'd love to hear your feedback! Contact us at \(supportEmail)
"""
    }
    
    private func generateScreenshotDescriptions() -> [ScreenshotDescription] {
        [
            ScreenshotDescription(
                fileName: "screenshot_1_recording",
                caption: "Record with Real-Time Feedback",
                device: .iPhone14Pro
            ),
            ScreenshotDescription(
                fileName: "screenshot_2_transcription",
                caption: "Instant AI Transcription",
                device: .iPhone14Pro
            ),
            ScreenshotDescription(
                fileName: "screenshot_3_coaching",
                caption: "Personalized AI Coaching",
                device: .iPhone14Pro
            ),
            ScreenshotDescription(
                fileName: "screenshot_5_goals",
                caption: "Track Your Progress",
                device: .iPhone14Pro
            ),
            ScreenshotDescription(
                fileName: "screenshot_6_themes",
                caption: "Beautiful Themes",
                device: .iPhone14Pro
            ),
            // iPad screenshots
            ScreenshotDescription(
                fileName: "screenshot_ipad_1",
                caption: "Optimized for iPad",
                device: .iPadPro129
            ),
            ScreenshotDescription(
                fileName: "screenshot_ipad_2",
                caption: "Multitasking Support",
                device: .iPadPro129
            )
        ]
    }
    
    // MARK: - App Store Links
    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openAppStore() {
        guard let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)") else { return }
        openURL(url)
    }

    func openReviewPage() {
        guard let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review") else { return }
        openURL(url)
    }

    func shareApp() {
        let shareText = "Check out Kochi - AI Presentation Coach!"
        let shareURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!

        let picker = NSSharingServicePicker(items: [shareText, shareURL])
        if let contentView = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }
}

// MARK: - Supporting Types
struct AppStoreMetadata {
    let appName: String
    let subtitle: String
    let keywords: [String]
    let description: String
    let whatsNew: String
    let categories: [AppCategory]
    let screenshots: [ScreenshotDescription]
    let appPreviewVideoURL: URL?
    
    var keywordsString: String {
        keywords.joined(separator: ", ")
    }
}

enum AppCategory {
    case education
    case productivity
    case business
    case utilities
    case lifestyle
}

struct ScreenshotDescription {
    let fileName: String
    let caption: String
    let device: DeviceType
    
    enum DeviceType {
        case iPhone14Pro
        case iPhone14ProMax
        case iPhoneSE
        case iPadPro129
        case iPadPro11
        
        var dimensions: CGSize {
            switch self {
            case .iPhone14Pro: return CGSize(width: 1179, height: 2556)
            case .iPhone14ProMax: return CGSize(width: 1290, height: 2796)
            case .iPhoneSE: return CGSize(width: 750, height: 1334)
            case .iPadPro129: return CGSize(width: 2048, height: 2732)
            case .iPadPro11: return CGSize(width: 1668, height: 2388)
            }
        }
    }
}

// MARK: - App Store Connect Helper Script
extension AppStoreHelper {
    func generateFastlaneMetadata() -> String {
        let metadata = generateAppStoreMetadata()
        
        return """
# Fastlane Metadata

## App Information
app_identifier "com.yourcompany.kochi"
apple_id "\(appStoreID)"

## Metadata
name "\(metadata.appName)"
subtitle "\(metadata.subtitle)"

## Keywords
keywords "\(metadata.keywordsString)"

## Description
\(metadata.description)

## What's New
\(metadata.whatsNew)

## Support Information
support_url "\(supportEmail)"
privacy_url "\(privacyPolicyURL)"

## Screenshots
\(metadata.screenshots.map { "# \($0.device): \($0.fileName) - \($0.caption)" }.joined(separator: "\n"))
"""
    }
    
    func generateAppStoreConnectChecklist() -> String {
        """
# App Store Connect Submission Checklist

## Pre-Submission
- [ ] Test on all supported devices
- [ ] Run performance profiling
- [ ] Check memory usage
- [ ] Verify offline functionality
- [ ] Test all IAP if applicable
- [ ] Review crash logs
- [ ] Update version and build numbers

## App Information
- [ ] App name: Kochi - AI Presentation Coach
- [ ] Bundle ID: com.yourcompany.kochi
- [ ] Primary category: Education
- [ ] Secondary category: Productivity
- [ ] Content rating: 4+

## Screenshots (Required)
- [ ] iPhone 6.7" (1290 × 2796)
- [ ] iPhone 6.1" (1179 × 2556)
- [ ] iPhone 5.5" (1242 × 2208)
- [ ] iPad Pro 12.9" (2048 × 2732)
- [ ] iPad Pro 11" (1668 × 2388)

## Metadata
- [ ] Description (up to 4000 characters)
- [ ] Keywords (up to 100 characters)
- [ ] What's New (up to 4000 characters)
- [ ] Support URL
- [ ] Privacy Policy URL
- [ ] Marketing URL (optional)

## Review Information
- [ ] Demo account (if needed)
- [ ] Review notes
- [ ] Contact information

## Legal
- [ ] License agreement
- [ ] Copyright information
- [ ] Export compliance

## Testing
- [ ] TestFlight internal testing
- [ ] TestFlight external testing
- [ ] Review feedback addressed

## Final Steps
- [ ] Submit for review
- [ ] Monitor review status
- [ ] Prepare marketing materials
- [ ] Plan launch announcement
"""
    }
}

// MARK: - Analytics Helper
extension AppStoreHelper {
    func trackEvent(_ event: AnalyticsEvent) {
        // Implement analytics tracking
        print("[Analytics] \(event.name): \(event.parameters ?? [:])")
    }
    
    struct AnalyticsEvent {
        let name: String
        let parameters: [String: Any]?
        
        static func appLaunch() -> AnalyticsEvent {
            AnalyticsEvent(name: "app_launch", parameters: nil)
        }
        
        static func featureUsed(_ feature: String) -> AnalyticsEvent {
            AnalyticsEvent(name: "feature_used", parameters: ["feature": feature])
        }
        
        static func goalCompleted(_ goalType: String) -> AnalyticsEvent {
            AnalyticsEvent(name: "goal_completed", parameters: ["goal_type": goalType])
        }
    }
}