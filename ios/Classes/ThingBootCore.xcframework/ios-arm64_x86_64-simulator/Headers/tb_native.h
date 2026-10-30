#ifndef TB_NATIVE_H
#define TB_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define TB_NATIVE_API __declspec(dllexport)
#else
#define TB_NATIVE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

TB_NATIVE_API int32_t tb_native_abi_version(void);
TB_NATIVE_API int32_t tb_md5(const char* data, size_t length, int32_t output_length,
    char* output, size_t output_size);
TB_NATIVE_API int32_t tb_url_encode(const char* data, size_t length,
    char* output, size_t output_size);
TB_NATIVE_API int32_t tb_mqtt_topic(const char* product_key, const char* device_key,
    int32_t topic, const char* side, const char* pvt_topic, const char* pvt_client,
    const char* pvt_key, int32_t azure, char* output, size_t output_size);
TB_NATIVE_API int32_t tb_sys_message(const char* mid, const char* data,
    uint32_t device, int64_t ts, char* output, size_t output_size);

#ifdef __cplusplus
}
#endif

#endif
