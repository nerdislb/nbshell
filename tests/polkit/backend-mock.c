#include <glib-object.h>
void polkit_agent_session_initiate(void *session) { g_signal_emit_by_name(session,"request","Mock response:",FALSE); }
void polkit_agent_session_cancel(void *session) { g_signal_emit_by_name(session,"completed",FALSE); }
void polkit_agent_session_response(void *session, const char *response) { }
