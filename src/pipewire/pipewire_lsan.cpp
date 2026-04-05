// PipeWire loads SPA plugins via dlopen() inside pw_context_new(). The plugin
// memory is released at pw_context_destroy() time, but dlclose() runs via
// atexit — after LSAN's own leak check — so LSAN sees them as leaks.
// __lsan_default_suppressions() is called automatically by LSAN at startup.
extern "C" const char* __lsan_default_suppressions() {
  return "leak:pw_context_load_module\n"
         "leak:pw_context_new\n";
}
