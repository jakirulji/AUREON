#define AUREON_LOCAL_FILES_PLUGIN_IMPL
#include "aureon_local_files/aureon_local_files_plugin_c_api.h"

#include "aureon_local_files/aureon_local_files_plugin.h"

#include <flutter/plugin_registrar_windows.h>

void AureonLocalFilesPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  AureonLocalFilesPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
