#ifndef VULKAN_SWIFT_VOLK_PROBE_H
#define VULKAN_SWIFT_VOLK_PROBE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t vulkanVersion;
    const char* driverName;
    const char* error;
    int validationEnabled;
} VulkanProbeResult;

VulkanProbeResult vulkan_probe(void);

#ifdef __cplusplus
}
#endif

#endif
