#ifndef EMILIA_WHISPER_H
#define EMILIA_WHISPER_H
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct EmiliaWhisper EmiliaWhisper;
EmiliaWhisper * emilia_whisper_create(const char * model_path);
void emilia_whisper_cancel(EmiliaWhisper * context);
void emilia_whisper_free(EmiliaWhisper * context);
char * emilia_whisper_transcribe(EmiliaWhisper * context, const float * samples, int count);
void emilia_whisper_free_text(char * text);
#ifdef __cplusplus
}
#endif
#endif
