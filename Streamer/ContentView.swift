import SwiftUI

struct ContentView: View {
    @StateObject private var streamer = CameraStreamer()
    @State private var serverIP: String = ""
    @State private var serverPort: String = "5000"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Connection Status")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    Text(streamer.connectionStatus)
                        .font(.headline)
                        .foregroundColor(streamer.isStreaming ? .green : .red)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Server Settings")
                        .font(.title3)
                        .bold()
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("IP Address")
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            TextField("e.g. 192.168.1.100", text: $serverIP)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(streamer.isStreaming)
                        }
                        
                        HStack {
                            Text("Port")
                                .foregroundColor(.secondary)
                                .frame(width: 90, alignment: .leading)
                            TextField("5000", text: $serverPort)
                                .keyboardType(.numberPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disabled(streamer.isStreaming)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                
                if streamer.isStreaming {
                    VStack(spacing: 6) {
                        Text("Active Transmission details:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Text("Frames Encoded & Sent:")
                            Text("\(streamer.framesSentCount)")
                                .bold()
                                .foregroundColor(.blue)
                        }
                    }
                    .transition(.opacity)
                }
                
                Spacer()
                
                Button(action: {
                    if streamer.isStreaming {
                        streamer.stopStreaming()
                    } else {
                        if let portValue = UInt16(serverPort) {
                            streamer.startStreaming(host: serverIP, port: portValue)
                        } else {
                            streamer.errorMessage = "Please enter a valid Port number between 1 and 65535."
                        }
                    }
                }) {
                    Text(streamer.isStreaming ? "Stop Stream" : "Start Stream")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(streamer.isStreaming ? Color.red : Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("UDP Cam Streamer")
            .alert(item: Binding<AlertMessage?>(
                get: { streamer.errorMessage.map { AlertMessage(message: $0) } },
                set: { streamer.errorMessage = $0?.message }
            )) { alertMessage in
                Alert(
                    title: Text("Notice"),
                    message: Text(alertMessage.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    let message: String
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
