import AVFoundation

enum BufferConversionError: Error {
    case noConverter
    case noOutputBuffer
}

/// Converts captured audio into the format the speech analyzer wants (sample rate, channels, sample type).
final class BufferConverter {
    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if inputFormat == format { return buffer }

        if converter == nil || converter?.inputFormat != inputFormat || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            // Don't prime: priming drops the first few samples of every buffer.
            converter?.primeMethod = .none
        }
        guard let converter else { throw BufferConversionError.noConverter }

        let ratio = format.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw BufferConversionError.noOutputBuffer
        }

        var error: NSError?
        var supplied = false
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error { throw error ?? BufferConversionError.noConverter }
        return output
    }
}
