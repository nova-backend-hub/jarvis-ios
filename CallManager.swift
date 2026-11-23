import Foundation
import CallKit
import AVFoundation

final class CallManager: NSObject, ObservableObject, CXProviderDelegate {
    static let shared = CallManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var currentCallUUID: UUID?
    private var socketTask: URLSessionWebSocketTask?
    @Published var serverUrl: String {
        didSet { UserDefaults.standard.set(serverUrl, forKey: "jarvis_server_url") }
    }
    @Published var isConnected = false

    override init() {
        self.serverUrl = UserDefaults.standard.string(forKey: "jarvis_server_url") ?? "http://192.168.1.150:8787"
        let config = CXProviderConfiguration(localizedName: "JARVIS")
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        self.provider = CXProvider(configuration: config)
        super.init()
        self.provider.setDelegate(self, queue: nil)
        connectWebSocket()
    }

    func connectWebSocket() {
        socketTask?.cancel(with: .goingAway, reason: nil)
        let wsUrlStr = serverUrl
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/ws"
        guard let url = URL(string: wsUrlStr) else { return }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.socketTask = task
        task.resume()
        isConnected = true
        listen()
    }

    private func listen() {
        socketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                if let data = text.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = obj["type"] as? String,
                   type == "incoming_call",
                   let call = obj["call"] as? [String: Any] {
                    let reason = (call["reason"] as? String) ?? "JARVIS Calling"
                    DispatchQueue.main.async {
                        self.reportIncomingCall(reason: reason)
                    }
                }
                self.listen()
            case .failure:
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.isConnected = false
                    self.connectWebSocket()
                }
            default:
                self.listen()
            }
        }
    }

    func reportIncomingCall(reason: String) {
        let uuid = UUID()
        self.currentCallUUID = uuid
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: reason)
        update.localizedCallerName = "JARVIS — \(reason)"
        update.hasVideo = false
        provider.reportNewIncomingCall(with: uuid, update: update) { _ in }
    }

    func endActiveCall() {
        guard let uuid = currentCallUUID else { return }
        let action = CXEndCallAction(call: uuid)
        callController.request(CXTransaction(action: action)) { _ in }
        currentCallUUID = nil
    }

    func providerDidReset(_ provider: CXProvider) {
        currentCallUUID = nil
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        NotificationCenter.default.post(name: NSNotification.Name("JARVISAnsweredCall"), object: nil)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        currentCallUUID = nil
        action.fulfill()
    }
}
