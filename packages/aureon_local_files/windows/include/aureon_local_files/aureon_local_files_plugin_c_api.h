#ifndef FLUTTER_PLUGIN_AUREON_LOCAL_FILES_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_AUREON_LOCAL_FILES_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef AUREON_LOCAL_FILES_PLUGIN_IMPL
#define AUREON_LOCAL_FILES_PLUGIN_EXPORT __declspec(dllexport)
#else
#define AUREON_LOCAL_FILES_PLUGIN_EXPORT __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

AUREON_LOCAL_FILES_PLUGIN_EXPORT void
AureonLocalFilesPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#ifdef __cplusplus
}
#endif

#endif  // FLUTTER_PLUGIN_AUREON_LOCAL_FILES_PLUGIN_C_API_H_
