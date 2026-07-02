import Foundation
import CWhisper

/// Loads a ggml Whisper model once and keeps it resident. Thread-safe for
/// serial use (we only ever transcribe one clip at a time).
final class Transcriber {
    private var ctx: OpaquePointer?

    init?(modelPath: String) {
        var cparams = whisper_context_default_params()
        // Metal is on by default when the lib is built with GGML_METAL; leave GPU enabled.
        cparams.use_gpu = true
        // Disable flash attention: it raises peak Metal scratch allocation, and under
        // memory pressure the buffer alloc can fail inside ggml, which aborts() the
        // whole process (we can't catch a C abort). Costs negligible speed/accuracy.
        cparams.flash_attn = false
        ctx = modelPath.withCString { whisper_init_from_file_with_params($0, cparams) }
        if ctx == nil {
            NSLog("gab: failed to load whisper model at \(modelPath)")
            return nil
        }
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    /// Transcribe 16kHz mono float32 PCM. Returns trimmed text, or "" on failure.
    func transcribe(_ samples: [Float]) -> String {
        guard let ctx, !samples.isEmpty else { return "" }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_timestamps = true
        params.single_segment = false
        params.no_context = true          // each dictation is independent
        params.suppress_blank = true
        params.suppress_nst = true        // drop non-speech tokens (reduces "[silence]" junk)
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
        // Hardcode English for v1; revisit for auto-detect later.
        let lang = "en"

        let ok = lang.withCString { langPtr -> Bool in
            params.language = langPtr
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count)) == 0
            }
        }
        guard ok else { return "" }

        let n = whisper_full_n_segments(ctx)
        var out = ""
        for i in 0..<n {
            if let cstr = whisper_full_get_segment_text(ctx, i) {
                out += String(cString: cstr)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
