#include <stdint.h>
typedef struct GlEngine GlEngine;
typedef struct { uint32_t suppress, kind, code; uint64_t flags; } GlOutcome;
GlEngine *gl_new(void);
void gl_free(GlEngine *engine);
uint32_t gl_configure(GlEngine *engine, const char *json);
const char *gl_error(const GlEngine *engine);
GlOutcome gl_process(GlEngine *engine, uint32_t event, uint32_t code, double x, double y);
void gl_disable(GlEngine *engine);
uint32_t gl_is_own(int64_t marker);
int64_t gl_marker(void);
