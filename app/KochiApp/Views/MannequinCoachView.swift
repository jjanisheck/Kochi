import SwiftUI
import WebKit

/// The same skinned mannequin and response director used in the browser workshop,
/// packaged locally. This surface never connects to the workshop or the internet.
struct MannequinCoachView: View {
    @ObservedObject var manager: VideoCoachingManager

    var body: some View {
        MannequinCoachPlayer(reaction: manager.avatarReaction,
                             meetingActive: manager.avatarMeetingActive,
                             thinking: manager.avatarThinking)
    }
}

private struct MannequinCoachPlayer: View {
    let reaction: CoachReaction
    let meetingActive: Bool
    let thinking: Bool
    var rehearsal = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themes: ThemeStore
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 105/255, green: 105/255, blue: 99/255)
                if let poster = CoachMannequinResources.poster {
                    poster.resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                MannequinCoachSurface(reaction: reaction,
                                      meetingActive: meetingActive,
                                      thinking: thinking,
                                      paused: scenePhase == .background,
                                      reduceMotion: reduceMotion, rehearsal: rehearsal,
                                      tint: CoachMannequinResources.materialHex(themes.palette.buttonLo)) { ready, error in
                    loaded = ready
                    failed = error
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .opacity(loaded ? 1 : 0)
                if !loaded {
                    VStack {
                        Spacer()
                        if failed {
                            Text("Coach animation unavailable")
                                .font(.caption2).foregroundStyle(.white)
                        } else {
                            ProgressView().tint(.white)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mannequin coach")
        .accessibilityValue(reaction.caption)
    }
}

enum CoachMannequinResources {
    static var folder: URL? { Bundle.main.url(forResource: "CoachMannequin", withExtension: nil) }
    static var poster: Image? {
        guard let url = folder?.appendingPathComponent("poster.png") else { return nil }
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: image)
        #endif
    }

    /// Use the actual primary button pigment rather than an unrelated orange.
    static func materialHex(_ color: Color) -> String {
        let red: CGFloat, green: CGFloat, blue: CGFloat
        #if os(macOS)
        guard let resolved = NSColor(color).usingColorSpace(.sRGB) else { return "#EC5000" }
        red = resolved.redComponent; green = resolved.greenComponent; blue = resolved.blueComponent
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#EC5000" }
        red = r; green = g; blue = b
        #endif
        return String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

@MainActor struct MannequinCoachSurface {
    let reaction: CoachReaction
    let meetingActive: Bool
    let thinking: Bool
    let paused: Bool
    let reduceMotion: Bool
    var rehearsal = false
    var tint = "#EC5000"
    let onLoad: (Bool, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLoad: onLoad) }

    func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "coach")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        #if os(iOS)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isUserInteractionEnabled = false
        #endif
        context.coordinator.webView = view
        configure(context.coordinator)
        context.coordinator.load()
        return view
    }

    func configure(_ coordinator: Coordinator) {
        coordinator.update(reaction: reaction, meetingActive: meetingActive,
                           thinking: thinking, paused: paused, reduceMotion: reduceMotion,
                           rehearsal: rehearsal, tint: tint)
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        private let onLoad: (Bool, Bool) -> Void
        private var ready = false
        private var latestReaction: CoachReaction = .idle
        private var latestThinking = false
        private var latestActive = false
        private var paused = false
        private var reduceMotion = false
        private var rehearsal = false
        private var tint = "#EC5000"
        private var lastDelivery: String?
        private var sessionID = UUID().uuidString
        private var sequence = 0
        private var reloads = 0
        private var stopped = false
        private var contextRecovery: Task<Void, Never>?
        #if DEBUG
        private var tested = false
        #endif

        init(onLoad: @escaping (Bool, Bool) -> Void) { self.onLoad = onLoad }

        func load() {
            guard !stopped, let view = webView,
                  let folder = CoachMannequinResources.folder else { onLoad(false, true); return }
            ready = false
            lastDelivery = nil
            // A process recovery starts a fresh director/session, retaining the
            // latest native response, not an earlier queued performance.
            sessionID = UUID().uuidString
            view.loadFileURL(folder.appendingPathComponent("index.html"), allowingReadAccessTo: folder)
        }

        func update(reaction: CoachReaction, meetingActive: Bool, thinking: Bool,
                    paused: Bool, reduceMotion: Bool, rehearsal: Bool, tint: String) {
            latestReaction = reaction
            latestActive = meetingActive
            latestThinking = thinking && meetingActive
            self.rehearsal = rehearsal
            let configurationChanged = self.paused != paused || self.reduceMotion != reduceMotion || self.tint != tint
            self.paused = paused
            self.reduceMotion = reduceMotion
            self.tint = tint
            guard ready else { return }
            if configurationChanged { configurePlayback() }
            deliverLatest()
        }

        private func configurePlayback() {
            webView?.callAsyncJavaScript("window.kochiCoach.configure(options)",
                arguments: ["options": ["paused": paused, "reduceMotion": reduceMotion, "tint": tint]],
                in: nil, in: .page) { _ in }
        }

        private func deliverLatest() {
            let key = "\(latestReaction.id):\(latestActive):\(latestThinking)"
            guard ready, key != lastDelivery else { return }
            lastDelivery = key
            let reaction = !latestActive ? CoachReaction.idle : latestThinking
                ? CoachReaction(intent: .thinking, expression: .thoughtful, caption: "Considering the conversation…")
                : latestReaction
            sequence += 1
            let packet: [String: Any] = [
                "intent": reaction.intent.rawValue, "expression": reaction.expression.rawValue,
                "gesture": reaction.gesture.rawValue, "intensity": reaction.intensity,
                "caption": reaction.caption, "verifiedGoal": reaction.intent == .goal,
                "source": "app", "sessionId": sessionID, "sequence": sequence,
                "eventId": "\(sessionID):\(sequence)"
            ]
            webView?.callAsyncJavaScript("return window.kochiCoach.receive(cue, options)",
                arguments: ["cue": packet, "options": ["preview": rehearsal]], in: nil, in: .page) { [weak self] result in
                    if case .failure = result { self?.onLoad(false, true) }
                }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !stopped, let value = message.body as? [String: Any], let type = value["type"] as? String else { return }
            switch type {
            case "ready":
                contextRecovery?.cancel()
                ready = true
                configurePlayback()
                deliverLatest()
                onLoad(true, false)
                #if DEBUG
                if CommandLine.arguments.contains("--selftest-mannequin"), !tested, let view = webView {
                    tested = true
                    MannequinCoachVerification.run(view)
                }
                #endif
            case "contextLost":
                ready = false
                onLoad(false, false)
                contextRecovery?.cancel()
                contextRecovery = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled, let self, !self.stopped else { return }
                    if self.reloads < 2 { self.reloads += 1; self.load() }
                    else { self.onLoad(false, true) }
                }
            case "contextRestored":
                contextRecovery?.cancel()
                ready = true
                configurePlayback()
                deliverLatest()
                onLoad(true, false)
            case "error":
                print("Mannequin coach: \(value["message"] ?? "rendering failed")")
                onLoad(false, true)
            default: break
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard !stopped else { return }
            onLoad(false, reloads >= 2)
            if reloads < 2 { reloads += 1; load() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onLoad(false, true) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onLoad(false, true) }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, url.isFileURL,
                  let folder = CoachMannequinResources.folder,
                  url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") else {
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }

        func stop() {
            stopped = true
            contextRecovery?.cancel()
            webView?.evaluateJavaScript("window.kochiCoach?.dispose()", completionHandler: nil)
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "coach")
            webView?.navigationDelegate = nil
            webView?.stopLoading()
        }
    }
}

/// Preview the installed character and the same semantic responses used in a
/// meeting. Proportion editing remains in the desktop browser workshop.
#if os(macOS)
struct CharacterWorkshopView: View {
    @State private var reaction = CoachReaction.listening
    private let examples: [(String, CoachIntent, CoachExpression, CoachGesture, String)] = [
        ("Listen", .listen, .attentive, .none, "Listen closely and give them room to respond."),
        ("Acknowledge", .steady, .attentive, .acknowledge, "Good point. Give them a moment to respond."),
        ("Agree", .steady, .encouraging, .agree, "That question helped clarify what matters."),
        ("Consider", .check, .thoughtful, .tilt, "Check whether that answers the question they asked."),
        ("Refocus", .focus, .firm, .point, "Bring the discussion back to the decision you need."),
        ("Encourage", .steady, .pleased, .celebrate, "You made space for a useful contribution."),
        ("Breathe", .pause, .relieved, .sigh, "Take a breath. You have a clear next step."),
        ("Uncertain", .check, .uncertain, .shrug, "Ask what they mean before drawing a conclusion."),
        ("Celebrate", .goal, .pleased, .salute, "Goal achieved. You asked the follow-up question."),
        ("Wrap up", .wrap, .pleased, .wave, "Summarize the decision and confirm the next step.")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MannequinCoachPlayer(reaction: reaction, meetingActive: true, thinking: false, rehearsal: true)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("MANNEQUIN COACH")
                    .font(KFont.mono(11)).tracking(1.4)
                Text(reaction.caption)
                    .font(KFont.zilla(17, .medium))
                    .frame(minHeight: 42, alignment: .topLeading)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(examples.indices, id: \.self) { index in
                        let example = examples[index]
                        Button(example.0) {
                            reaction = CoachReaction(intent: example.1, expression: example.2,
                                gesture: example.3, intensity: example.1 == .goal ? 0.75 : 0.4,
                                caption: example.4)
                        }
                        .font(KFont.sans(12, .medium))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(KColor.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                Text("35 authored animations · fixed bust camera")
                    .font(KFont.mono(10)).foregroundStyle(KColor.inkSoft)
                Text("Rehearse a response without a meeting or microphone. Each gesture returns to breathing. Edit the character and its animations in the browser workshop on your Mac.")
                    .font(KFont.sans(12, .regular)).foregroundStyle(KColor.inkSoft)
            }
            .padding(16)
            .foregroundStyle(KColor.ink)
        }
    }
}
#endif

#if os(macOS)
extension MannequinCoachSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ view: WKWebView, context: Context) { configure(context.coordinator) }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { coordinator.stop() }
}
#else
extension MannequinCoachSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ view: WKWebView, context: Context) { configure(context.coordinator) }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { coordinator.stop() }
}
#endif

#if DEBUG
/// Exercises the actual bundled player in WKWebView on either platform, without
/// microphone capture or an AI request. Results are readable from the app container.
@MainActor private enum MannequinCoachVerification {
    static func run(_ view: WKWebView) {
        view.callAsyncJavaScript("""
            const c=window.kochiCoach,wait=ms=>new Promise(r=>setTimeout(r,ms));
            const checks=[];const check=(ok,label)=>{checks.push({ok:!!ok,label});};
            const start=c.snapshot(),camera=JSON.stringify(start.camera);
            check(start.animations.length===35,'35 authored clips bundled');
            check(start.current==='Breathing Idle','starts breathing');
            await wait(700);
            check(c.snapshot().time!==start.time && c.snapshot().frames>start.frames,'breathing advances on screen');
            for(const [gesture,animation,expression] of [
                ['acknowledge','acknowledging','attentive'],['agree','head nod yes','attentive'],
                ['point','Pointing','firm'],['sigh','relieved sigh','relieved'],
                ['shrug','Shrugging','uncertain'],['talk','Talking','attentive']]){
                c.receive({intent:'prompt',expression,gesture,caption:'Native response verification'},{preview:true});
                await wait(180);
                check(c.snapshot().current===animation,gesture+' selects '+animation);
                check(JSON.stringify(c.snapshot().camera)===camera,gesture+' keeps camera fixed');
            }
            c.receive({intent:'steady',expression:'pleased',gesture:'celebrate'},{preview:true});
            check(c.snapshot().current==='happy hand gesture','praise stays restrained');
            c.receive({intent:'goal',verifiedGoal:true,gesture:'salute',intensity:.75},{preview:true});
            check(c.snapshot().current==='Salute','verified goal salutes');
            await wait(5200);
            check(c.snapshot().current==='Breathing Idle','one-shot returns to breathing');
            c.configure({paused:true});await wait(120);const frozen=c.snapshot().time;
            await wait(400);check(c.snapshot().time===frozen,'background pauses animation');
            c.configure({paused:false,reduceMotion:true});await wait(250);const reduced=c.snapshot().time;
            c.receive({intent:'goal',verifiedGoal:true,intensity:1});await wait(350);
            check(c.snapshot().current==='Breathing Idle' && c.snapshot().time===reduced,'Reduced Motion stays still');
            c.configure({paused:false,reduceMotion:false});await wait(400);
            check(c.snapshot().time!==reduced,'foreground resumes breathing');
            check(c.inspect().visiblePixels>1000,'mannequin occupies the bust crop');
            return {checks,failures:checks.filter(c=>!c.ok).length,snapshot:c.snapshot(),inspection:c.inspect()};
            """, arguments: [:], in: nil, in: .page) { result in
            let report: [String: Any]
            switch result {
            case .success(let value): report = value as? [String: Any] ?? ["error": "Missing report"]
            case .failure(let error): report = ["error": error.localizedDescription]
            }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
               let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? data.write(to: documents.appendingPathComponent("mannequin-selftest.json"), options: .atomic)
            }
            print("Mannequin verification: \(report)")
        }
    }
}
#endif
