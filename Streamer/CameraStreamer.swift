import Foundation
import AVFoundation
import Network
import UIKit

class CameraStreamer: NSObject, ObservableObject {
    @Published var isStreaming = false
    @Published var connectionStatus = "Disconnected"
    @Published var framesSentCount = 0
    @Published var errorMessage: String? = nil
    
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.example.Streamer.captureQueue")
    private let networkQueue = DispatchQueue(label: "com.example.Streamer.networkQueue")
    
    private var connection: NWConnection?
    private var currentHost: String = ""
    private var currentPort: UInt16 = 5000
    private var frameSequenceNumber: UInt32 = 0
    
    private let targetWidth: CGFloat = 480
    private let targetHeight: CGFloat = 640
    private let jpegQuality: CGFloat = 0.5
    private let maxChunkSize: Int = 60000
    
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    private func setupCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            
            if self.captureSession.canSetSessionPreset(.vga640x480) {
                self.captureSession.sessionPreset = .vga640x480
            } else if self.captureSession.canSetSessionPreset(.medium) {
                self.captureSession.sessionPreset = .medium
            }
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Rear camera not found."
                }
                return
            }
            
            do {
                let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.captureSession.canAddInput(videoDeviceInput) {
                    self.captureSession.addInput(videoDeviceInput)
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Could not add camera input."
                    }
                    return
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Camera input error: \(error.localizedDescription)"
                }
                return
            }
            
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Could not add camera output."
                }
                return
            }
            
            if let connection = self.videoOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            self.captureSession.commitConfiguration()
        }
    }
    
    func startStreaming(host: String, port: UInt16) {
        guard !host.isEmpty else {
            self.errorMessage = "Please enter a valid IP Address."
            return
        }
        
        self.currentHost = host
        self.currentPort = port
        
        networkQueue.async { [weak self] in
            guard let self = self else { return }
            
            let hostEndpoint = NWEndpoint.Host(self.currentHost)
            guard let portEndpoint = NWEndpoint.Port(rawValue: self.currentPort) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid Port Number."
                }
                return
            }
            
            let parameters = NWParameters.udp
            
            self.connection = NWConnection(host: hostEndpoint, port: portEndpoint, using: parameters)
            
            self.connection?.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self.connectionStatus = "Connected"
                        self.isStreaming = true
                        self.startCapture()
                    case .failed(let error):
                        self.connectionStatus = "Failed: \(error.localizedDescription)"
                        self.stopStreaming()
                    case .cancelled:
                        self.connectionStatus = "Disconnected"
                        self.stopStreaming()
                    case .waiting(let error):
                        self.connectionStatus = "Waiting: \(error.localizedDescription)"
                    default:
                        break
                    }
                }
            }
            
            self.connection?.start(queue: self.networkQueue)
        }
    }
    
    func stopStreaming() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
        
        networkQueue.async { [weak self] in
            guard let self = self else { return }
            self.connection?.cancel()
            self.connection = nil
            
            DispatchQueue.main.async {
                self.isStreaming = false
                self.connectionStatus = "Disconnected"
            }
        }
    }
    
    private func startCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }
    
    private func sendData(data: Data) {
        guard let connection = connection, isStreaming else { return }
        
        connection.send(content: data, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Send Error: \(error.localizedDescription)"
                }
            }
        }))
    }
}

extension CameraStreamer: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isStreaming else { return }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let finalImage = resizedImage,
              let jpegData = finalImage.jpegData(compressionQuality: jpegQuality) else { return }
        
        frameSequenceNumber += 1
        let totalSize = jpegData.count
        let numChunks = Int(ceil(Double(totalSize) / Double(maxChunkSize)))
        
        for chunkIndex in 0..<numChunks {
            let offset = chunkIndex * maxChunkSize
            let currentChunkSize = min(maxChunkSize, totalSize - offset)
            let subData = jpegData.subdata(in: offset..<(offset + currentChunkSize))
            
            var packet = Data()
            
            var frameIdBe = frameSequenceNumber.bigEndian
            packet.append(UnsafeBufferPointer(start: &frameIdBe, count: 1))
            
            var chunkIndexBe = UInt32(chunkIndex).bigEndian
            packet.append(UnsafeBufferPointer(start: &chunkIndexBe, count: 1))
            
            var totalChunksBe = UInt32(numChunks).bigEndian
            packet.append(UnsafeBufferPointer(start: &totalChunksBe, count: 1))
            
            packet.append(subData)
            
            sendData(data: packet)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.framesSentCount += 1
        }
    }
}
