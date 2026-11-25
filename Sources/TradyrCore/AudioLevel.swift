import AVFoundation

/// Level metering for diagnostics (is audio actually arriving on this lane?).
public enum AudioLevel {
    /// Root-mean-square level of a buffer, linear 0…1, averaged over channels.
    public static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        let format = buffer.format
        let interleaved = format.isInterleaved
        let channels = Int(format.channelCount)
        let framesPerChannel = Int(buffer.frameLength)
        guard framesPerChannel > 0, channels > 0 else { return 0 }

        // Interleaved buffers hold every channel in channel 0's pointer.
        let planes = interleaved ? 1 : channels
        let samplesPerPlane = interleaved ? framesPerChannel * channels : framesPerChannel

        var sumSquares = 0.0
        if let data = buffer.floatChannelData {
            for plane in 0..<planes {
                let p = data[plane]
                for i in 0..<samplesPerPlane { sumSquares += Double(p[i] * p[i]) }
            }
        } else if let data = buffer.int16ChannelData {
            for plane in 0..<planes {
                let p = data[plane]
                for i in 0..<samplesPerPlane {
                    let s = Double(p[i]) / 32768
                    sumSquares += s * s
                }
            }
        } else {
            return 0
        }
        return Float((sumSquares / Double(planes * samplesPerPlane)).squareRoot())
    }

    /// Linear level to dBFS, floored at -120.
    public static func decibels(_ linear: Float) -> Float {
        linear > 0 ? max(20 * log10(linear), -120) : -120
    }
}
