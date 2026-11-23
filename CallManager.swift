import Foundation
import CallKit
import AVFoundation

final class CallManager: NSObject, ObservableObject, CXProviderDelegate {
    static let shared = CallManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var currentCallUUID: UUID?
    private var socketTask: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var silentEngine: AVAudioEngine?

    @Published var serverUrl: String {
        didSet { UserDefaults.standard.set(serverUrl, forKey: "jarvis_server_url") }
    }
    @Published var accessToken: String {
        didSet { UserDefaults.standard.set(accessToken, forKey: "jarvis_access_token") }
    }
    @Published var keepAliveAudio: Bool {
        didSet {
            UserDefaults.standard.set(keepAliveAudio, forKey: "jarvis_keepalive_audio")
            if keepAliveAudio { startSilentKeepalive() } else { stopSilentKeepalive() }
        }
    }
    @Published var isConnected = false

    override init() {
        self.serverUrl = UserDefaults.standard.string(forKey: "jarvis_server_url") ?? "https://jarvis-backend-160271972570.us-central1.run.app"
        self.accessToken = UserDefaults.standard.string(forKey: "jarvis_access_token") ?? ""
        self.keepAliveAudio = UserDefaults.standard.object(forKey: "jarvis_keepalive_audio") as? Bool ?? true

        let config = CXProviderConfiguration(localizedName: "JARVIS")
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        self.provider = CXProvider(configuration: config)
        super.init()
        self.provider.setDelegate(self, queue: nil)
        if keepAliveAudio { startSilentKeepalive() }
        connectWebSocket()
    }

    /// Silent zero-gain audio session keeps the iOS process & CallKit WebSocket awake even when locked for 10+ minutes.
    func startSilentKeepalive() {
        stopSilentKeepalive()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000)!
        buf.frameLength = 8000
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.0
        try? engine.start()
        player.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
        player.play()
        self.silentEngine = engine
    }

    func stopSilentKeepalive() {
        silentEngine?.stop()
        silentEngine = nil
    }

    func connectWebSocket() {
        pingTimer?.invalidate()
        socketTask?.cancel(with: .goingAway, reason: nil)

        var wsUrlStr = serverUrl
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/ws"
        if !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let escaped = accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? accessToken
            wsUrlStr += "?token=\(escaped)"
        }
        guard let url = URL(string: wsUrlStr) else { return }
        let task = URLSession(configuration: .default).webSocketTask(with: url)
        self.socketTask = task
        task.resume()
        isConnected = true
        listen()

        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.socketTask?.sendPing { error in
                if error != nil {
                    DispatchQueue.main.async {
                        self?.isConnected = false
                        self?.connectWebSocket()
                    }
                }
            }
        }
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
        callController.request(CXTransaction(action: CXEndCallAction(call: uuid))) { _ in }
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
        if keepAliveAudio { startSilentKeepalive() }
        action.fulfill()
    }
}
