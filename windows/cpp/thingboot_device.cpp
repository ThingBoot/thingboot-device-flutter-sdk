extern "C" __declspec(dllexport) int tb_native_abi_version(void);

extern "C" __declspec(dllexport) int thingboot_device_plugin_anchor() {
  return tb_native_abi_version();
}
