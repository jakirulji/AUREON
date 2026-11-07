#include "aureon_local_files/aureon_local_files_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <chrono>
#include <filesystem>
#include <string>
#include <system_error>
#include <vector>

using Microsoft::WRL::ComPtr;
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {
std::string Utf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string output(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
      output.data(), size, nullptr, nullptr);
  return output;
}

std::filesystem::path PathFromUtf8(const std::string& value) {
  const auto* begin = reinterpret_cast<const char8_t*>(value.data());
  return std::filesystem::path(std::u8string(begin, begin + value.size()));
}

std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring output(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), output.data(), size);
  return output;
}

const std::string* GetString(const EncodableMap* map, const char* key) {
  if (!map) return nullptr;
  auto it = map->find(EncodableValue(key));
  if (it == map->end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

void PickRoot(std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const HRESULT init = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  const bool uninitialize = SUCCEEDED(init);
  ComPtr<IFileOpenDialog> dialog;
  HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&dialog));
  if (FAILED(hr)) {
    if (uninitialize) CoUninitialize();
    result->Error("picker_failed", "Windows folder picker could not be created.");
    return;
  }
  FILEOPENDIALOGOPTIONS options;
  hr = dialog->GetOptions(&options);
  if (SUCCEEDED(hr)) hr = dialog->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
  if (SUCCEEDED(hr)) hr = dialog->Show(GetActiveWindow());
  if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    if (uninitialize) CoUninitialize();
    result->Success();
    return;
  }
  ComPtr<IShellItem> item;
  if (SUCCEEDED(hr)) hr = dialog->GetResult(&item);
  PWSTR path = nullptr;
  if (SUCCEEDED(hr)) hr = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
  if (FAILED(hr) || path == nullptr) {
    if (path) CoTaskMemFree(path);
    if (uninitialize) CoUninitialize();
    result->Error("picker_failed", "Windows did not return a valid folder path.");
    return;
  }
  const std::wstring wide_path(path);
  CoTaskMemFree(path);
  const std::string utf8_path = Utf8(wide_path);
  if (uninitialize) CoUninitialize();
  result->Success(EncodableValue(EncodableMap{
      {EncodableValue("rootId"), EncodableValue(utf8_path)},
      {EncodableValue("displayName"), EncodableValue(Utf8(std::filesystem::path(wide_path).filename().wstring()).empty() ? utf8_path : Utf8(std::filesystem::path(wide_path).filename().wstring()))},
      {EncodableValue("rootDocumentId"), EncodableValue(utf8_path)}
  }));
}

void OpenFile(const EncodableMap* args,
              std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* root = GetString(args, "rootId");
  const auto* file = GetString(args, "fileId");
  if (!root || !file || root->empty() || file->empty()) { result->Error("invalid_arguments", "rootId and fileId are required."); return; }
  std::error_code ec;
  const auto canonical_root = std::filesystem::weakly_canonical(PathFromUtf8(*root), ec);
  if (ec) { result->Error("invalid_root", "The selected root is unavailable."); return; }
  const auto path = std::filesystem::weakly_canonical(PathFromUtf8(*file), ec);
  if (ec) { result->Error("not_found", "The selected file is unavailable."); return; }
  const auto relative = path.lexically_relative(canonical_root);
  if (relative.empty() || relative.is_absolute() || (!relative.empty() && *relative.begin() == std::filesystem::path(".."))) {
    result->Error("outside_root", "The requested file is outside the selected AUREON root."); return;
  }
  if (!std::filesystem::is_regular_file(path, ec) || ec) { result->Error("not_a_file", "The selected item is not an accessible file."); return; }
  const auto opened = reinterpret_cast<INT_PTR>(ShellExecuteW(nullptr, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
  if (opened <= 32) { result->Error("open_failed", "Windows could not open this file."); return; }
  result->Success(EncodableValue(true));
}


bool IsWithinRoot(const std::filesystem::path& root, const std::filesystem::path& candidate) {
  const auto relative = candidate.lexically_relative(root);
  return relative.empty() || (!relative.is_absolute() &&
      *relative.begin() != std::filesystem::path(".."));
}
bool ValidLeafName(const std::string& name) {
  return !name.empty() && name != "." && name != ".." &&
      name.find('/') == std::string::npos && name.find('\\') == std::string::npos &&
      name.find_first_of("<>:\"|?*") == std::string::npos &&
      name.back() != '.' && name.back() != ' ';
}
void RenameEntry(const EncodableMap* args, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* root = GetString(args, "rootId");
  const auto* entry = GetString(args, "entryId");
  const auto* name = GetString(args, "newName");
  if (!root || !entry || !name || !ValidLeafName(*name)) { result->Error("invalid_arguments", "A valid new name and entry identity are required."); return; }
  std::error_code ec;
  const auto base = std::filesystem::canonical(PathFromUtf8(*root), ec);
  if (ec) { result->Error("invalid_root", "The selected root is unavailable."); return; }
  const auto source = std::filesystem::absolute(PathFromUtf8(*entry), ec).lexically_normal();
  if (ec || source == base || source.parent_path().empty()) { result->Error("invalid_target", "The selected root itself cannot be renamed."); return; }
  const auto parent = std::filesystem::canonical(source.parent_path(), ec);
  if (ec || !IsWithinRoot(base, parent)) { result->Error("outside_root", "The requested item is not inside the selected root."); return; }
  const auto status = std::filesystem::symlink_status(source, ec);
  if (ec || std::filesystem::is_symlink(status) ||
      (!std::filesystem::is_regular_file(status) && !std::filesystem::is_directory(status))) {
    result->Error("unsupported_item", "Symbolic links and unsupported filesystem items cannot be renamed here."); return;
  }
  const auto target = parent / PathFromUtf8(*name);
  if (std::filesystem::exists(target, ec) || ec) { result->Error("conflict", "An item with that name already exists. Nothing was overwritten."); return; }
  std::filesystem::rename(source, target, ec);
  if (ec) { result->Error("rename_failed", "The item could not be renamed."); return; }
  const auto value = target.u8string();
  result->Success(EncodableValue(std::string(reinterpret_cast<const char*>(value.data()), value.size())));
}
void CreateFolder(const EncodableMap* args, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* root = GetString(args, "rootId");
  const auto* parent = GetString(args, "parentId");
  const auto* name = GetString(args, "name");
  if (!root || !parent || !name || !ValidLeafName(*name)) { result->Error("invalid_arguments", "A valid folder name and parent identity are required."); return; }
  std::error_code ec;
  const auto base = std::filesystem::canonical(PathFromUtf8(*root), ec);
  if (ec) { result->Error("invalid_root", "The selected root is unavailable."); return; }
  const auto folder = std::filesystem::canonical(PathFromUtf8(*parent), ec);
  if (ec || !IsWithinRoot(base, folder) || !std::filesystem::is_directory(folder, ec) || ec) { result->Error("outside_root", "The target folder is not inside the selected root."); return; }
  const auto target = folder / PathFromUtf8(*name);
  if (std::filesystem::exists(target, ec) || ec) { result->Error("conflict", "An item with that name already exists. Nothing was overwritten."); return; }
  if (!std::filesystem::create_directory(target, ec) || ec) { result->Error("create_failed", "The new folder could not be created."); return; }
  const auto value = target.u8string();
  result->Success(EncodableValue(std::string(reinterpret_cast<const char*>(value.data()), value.size())));
}


void ListChildren(const EncodableMap* args,
                  std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* root = GetString(args, "rootId");
  const auto* parent = GetString(args, "parentId");
  if (!root || !parent || root->empty() || parent->empty()) {
    result->Error("invalid_arguments", "rootId and parentId are required.");
    return;
  }
  std::error_code ec;
  const auto canonical_root = std::filesystem::weakly_canonical(PathFromUtf8(*root), ec);
  if (ec) { result->Error("invalid_root", "The selected root is no longer accessible."); return; }
  const auto path = std::filesystem::weakly_canonical(PathFromUtf8(*parent), ec);
  if (ec) { result->Error("not_a_directory", "The selected path is not accessible."); return; }
  const auto relative = path.lexically_relative(canonical_root);
  if (relative.empty() || relative.is_absolute() ||
      (!relative.empty() && *relative.begin() == std::filesystem::path(".."))) {
    result->Error("outside_root", "The requested folder is outside the selected AUREON root.");
    return;
  }
  if (!std::filesystem::is_directory(path, ec) || ec) {
    result->Error("not_a_directory", "The selected path is not an accessible directory.");
    return;
  }
  struct Entry { bool directory; std::string name; EncodableMap value; };
  std::vector<Entry> entries;
  for (std::filesystem::directory_iterator it(path,
          std::filesystem::directory_options::skip_permission_denied, ec), end;
       !ec && it != end; it.increment(ec)) {
    const auto status = it->symlink_status(ec);
    if (ec) { ec.clear(); continue; }
    const bool directory = std::filesystem::is_directory(status);
    const auto filename = it->path().filename().u8string();
    const std::string name(reinterpret_cast<const char*>(filename.data()), filename.size());
    std::string id;
    const auto child = it->path().u8string();
    id.assign(reinterpret_cast<const char*>(child.data()), child.size());
    const DWORD attributes = GetFileAttributesW(it->path().c_str());
    const bool hidden = attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & (FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM)) != 0;
    EncodableMap map{
      {EncodableValue("id"), EncodableValue(id)},
      {EncodableValue("name"), EncodableValue(name)},
      {EncodableValue("isDirectory"), EncodableValue(directory)},
      {EncodableValue("isHidden"), EncodableValue(hidden)}
    };
    const auto modified = it->last_write_time(ec);
    if (!ec) {
      const auto system_time = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
          modified - std::filesystem::file_time_type::clock::now() +
          std::chrono::system_clock::now());
      const auto epoch_ms = std::chrono::duration_cast<std::chrono::milliseconds>(system_time.time_since_epoch()).count();
      map.emplace(EncodableValue("modifiedEpochMs"), EncodableValue(static_cast<int64_t>(epoch_ms)));
    }
    ec.clear();
    if (!directory && std::filesystem::is_regular_file(status)) {
      const auto size = it->file_size(ec);
      if (!ec) map.emplace(EncodableValue("sizeBytes"), EncodableValue(static_cast<int64_t>(size)));
      ec.clear();
    }
    entries.push_back({directory, name, std::move(map)});
  }
  if (ec) {
    result->Error("listing_failed", "A directory entry could not be read.");
    return;
  }
  std::sort(entries.begin(), entries.end(), [](const Entry& a, const Entry& b) {
    if (a.directory != b.directory) return a.directory > b.directory;
    return a.name < b.name;
  });
  EncodableList output;
  for (auto& entry : entries) output.emplace_back(std::move(entry.value));
  result->Success(EncodableValue(std::move(output)));
}
}  // namespace

AureonLocalFilesPlugin::AureonLocalFilesPlugin() = default;

AureonLocalFilesPlugin::~AureonLocalFilesPlugin() = default;

void AureonLocalFilesPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<AureonLocalFilesPlugin>();
  plugin->channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "aureon/local_files",
      &flutter::StandardMethodCodec::GetInstance());
  plugin->channel_->SetMethodCallHandler(
      [plugin_ptr = plugin.get()](const auto& call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

void AureonLocalFilesPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (call.method_name() == "pickRoot") {
    PickRoot(std::move(result));
    return;
  }
  if (call.method_name() == "listChildren") {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    ListChildren(args, std::move(result));
    return;
  }
  if (call.method_name() == "renameEntry") {
    RenameEntry(std::get_if<EncodableMap>(call.arguments()), std::move(result)); return;
  }
  if (call.method_name() == "createFolder") {
    CreateFolder(std::get_if<EncodableMap>(call.arguments()), std::move(result)); return;
  }
  if (call.method_name() == "openFile") {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    OpenFile(args, std::move(result));
    return;
  }
  result->NotImplemented();
}
