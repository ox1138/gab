import Foundation
import CWhisper

/// Loads a ggml Whisper model once and keeps it resident. A whisper context is
/// not reentrant — two overlapping `whisper_full` calls abort() inside ggml — so
/// `transcribe` is serialized with a lock.
final class Transcriber {
    private var ctx: OpaquePointer?
    private let lock = NSLock()
    /// False for `.en` models, which only know English and can't auto-detect.
    private(set) var isMultilingual = false

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
        isMultilingual = whisper_is_multilingual(ctx) != 0
    }

    deinit {
        if let ctx { whisper_free(ctx) }
    }

    /// Transcribe 16kHz mono float32 PCM. `language` is a Whisper code ("en", "pt")
    /// or "auto". Returns trimmed text, or "" on failure.
    func transcribe(_ samples: [Float], language: String) -> String {
        guard let ctx, !samples.isEmpty else { return "" }
        lock.lock(); defer { lock.unlock() }

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
        // English-only models fail language detection, so they always get "en".
        let lang = isMultilingual ? language : "en"

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
