#include "EmiliaWhisper.h"
#include "whisper.h"
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <string>

struct EmiliaWhisper { whisper_context * ctx; std::atomic<bool> cancelled{false}; };
static bool cancelled(void * user) { return static_cast<EmiliaWhisper *>(user)->cancelled.load(); }
EmiliaWhisper * emilia_whisper_create(const char * path) {
    auto params = whisper_context_default_params();
    params.use_gpu = true;
    auto ctx = whisper_init_from_file_with_params(path, params);
    return ctx ? new EmiliaWhisper{ctx} : nullptr;
}
void emilia_whisper_cancel(EmiliaWhisper * ctx) { if (ctx) ctx->cancelled.store(true); }
void emilia_whisper_free(EmiliaWhisper * ctx) { if (ctx) { whisper_free(ctx->ctx); delete ctx; } }
char * emilia_whisper_transcribe(EmiliaWhisper * ctx, const float * samples, int count) {
    if (!ctx || ctx->cancelled.load() || count < 16000) return nullptr;
    auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = 4;
    params.language = "en";
    params.translate = false;
    params.no_context = true;
    params.no_timestamps = true;
    params.single_segment = true;
    params.print_realtime = false;
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_special = false;
    params.suppress_blank = true;
    params.suppress_nst = true;
    params.temperature_inc = 0;
    params.abort_callback = cancelled;
    params.abort_callback_user_data = ctx;
    if (whisper_full(ctx->ctx, params, samples, count) != 0 || ctx->cancelled.load()) return nullptr;
    std::string text;
    for (int i = 0; i < whisper_full_n_segments(ctx->ctx); ++i) {
        if (whisper_full_get_segment_no_speech_prob(ctx->ctx, i) < 0.6f)
            text += whisper_full_get_segment_text(ctx->ctx, i);
    }
    return strdup(text.c_str());
}
void emilia_whisper_free_text(char * text) { free(text); }
