import SwiftUI

struct ContentView: View {
    @EnvironmentObject var callManager: CallManager
    @State private var showSettings = false
    @State private var draftUrl = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WebViewContainer(urlString: callManager.serverUrl)
                .ignoresSafeArea()

            Button {
                draftUrl = callManager.serverUrl
                showSettings = true
            } label: {
                Image(systemName: callManager.isConnected ? "waveform.circle.fill" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 20))
                    .foregroundColor(callManager.isConnected ? Color(red: 58/255, green: 184/255, blue: 121/255) : .red)
                    .padding(10)
                    .background(Color(red: 23/255, green: 31/255, blue: 38/255).opacity(0.85))
                    .clipShape(Circle())
            }
            .padding(.top, 52)
            .padding(.trailing, 14)
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section("JARVIS Host PC") {
                        TextField("http://192.168.1.150:8787", text: $draftUrl)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                        Button("Save & Reconnect CallKit") {
                            callManager.serverUrl = draftUrl
                            callManager.connectWebSocket()
                            showSettings = false
                        }
                    }
                    Section("CallKit Test") {
                        Button("Trigger Native CallKit Ring") {
                            callManager.reportIncomingCall(reason: "JARVIS Diagnostic Call")
                        }
                    }
                }
                .navigationTitle("JARVIS Connection")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showSettings = false }
                    }
                }
            }
        }
    }
}
