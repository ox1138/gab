import AVFoundation

/// Captures mic audio and resamples it to 16kHz mono float32 (what Whisper wants).
/// AVAudioEngine hands us the hardware format (usually 44.1/48kHz); an
/// AVAudioConverter does the rate/channel conversion per tap buffer.
final class AudioCapture {
    private let engine = AVAudioEngine()
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var running = false

    private let lock = NSLock()
    private var samples: [Float] = []

    init() {
        outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: 16_000,
                                     channels: 1,
                                     interleaved: false)!
    }

    func start() throws {
        guard !running else { return }
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    /// Stop capture and return the accumulated 16kHz samples.
    @discardableResult
    func stop() -> [Float] {
        guard running else { return currentSamples() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        return currentSamples()
    }

    private func currentSamples() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    private func append(_ inBuffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = outputFormat.sampleRate / inBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var err: NSError?
        let status = converter.convert(to: outBuffer, error: &err) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        guard status != .error, let ch = outBuffer.floatChannelData else { return }
        let n = Int(outBuffer.frameLength)
        guard n > 0 else { return }
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n))
        lock.unlock()
    }
}
