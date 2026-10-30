extern "C" __attribute__((visibility("default"))) int tb_native_abi_version(void);

extern "C" __attribute__((visibility("default"))) int thingboot_device_plugin_anchor() {
  return tb_native_abi_version();
}
