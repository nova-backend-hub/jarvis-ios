import SwiftUI
import WebKit
import UIKit

struct WebViewContainer: UIViewRepresentable {
    let urlString: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "jarvisNative")

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 15/255, green: 20/255, blue: 25/255, alpha: 1)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        context.coordinator.attach(webView: web)

        if let u = URL(string: urlString) {
            var req = URLRequest(url: u, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30)
            let tok = CallManager.shared.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tok.isEmpty {
                req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            }
            web.load(req)
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url?.host != URL(string: urlString)?.host, let u = URL(string: urlString) {
            var req = URLRequest(url: u, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30)
            let tok = CallManager.shared.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tok.isEmpty {
                req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            }
            uiView.load(req)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?

        func attach(webView: WKWebView) {
            self.webView = webView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleCallAnswered),
                name: NSNotification.Name("JARVISAnsweredCall"),
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleCallEnded),
                name: NSNotification.Name("JARVISEndedCall"),
                object: nil
            )
        }

        @objc private func handleCallAnswered() {
            let js = """
            (function() {
              const ans = document.getElementById('incoming-answer-btn');
              const ov = document.getElementById('incoming-overlay');
              if (ans && ov && !ov.classList.contains('hidden')) {
                ans.click();
              } else {
                const callBtn = document.getElementById('main-call-btn');
                if (callBtn && !callBtn.classList.contains('in-call')) callBtn.click();
              }
            })();
            """
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        @objc private func handleCallEnded() {
            let js = """
            (function() {
              const dec = document.getElementById('incoming-decline-btn');
              const ov = document.getElementById('incoming-overlay');
              if (dec && ov && !ov.classList.contains('hidden')) {
                dec.click();
              } else {
                const callBtn = document.getElementById('main-call-btn');
                if (callBtn && callBtn.classList.contains('in-call')) callBtn.click();
              }
            })();
            """
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let action = dict["action"] as? String else { return }
            if action == "incoming_call" {
                let reason = (dict["reason"] as? String) ?? "JARVIS Alert"
                let callId = (dict["callId"] as? String) ?? ""
                DispatchQueue.main.async {
                    CallManager.shared.reportIncomingCall(reason: reason, callId: callId)
                }
            } else if action == "end_call" {
                DispatchQueue.main.async {
                    CallManager.shared.endActiveCall()
                }
            }
        }

        // Open target="_blank" OAuth links (Google, Microsoft, Claude, ChatGPT) in Safari so user's browser session works cleanly
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               let host = url.host?.lowercased(),
               (host.contains("accounts.google.com") ||
                host.contains("login.microsoftonline.com") ||
                host.contains("microsoft.com") ||
                host.contains("claude.ai") ||
                host.contains("auth.openai.com")) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        @available(iOS 15.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }
    }
}
