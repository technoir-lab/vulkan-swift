// VolkProbe shim implemented with the minimal C API on top of Volk. Volk
// loads the Vulkan loader and its entry points at runtime, so the shim never
// links against libvulkan directly.

#include <volk/volk.h>

#include <stdio.h>

#include <TargetConditionals.h>

#include "VolkProbe.h"

static char g_error[512];
static char g_driverName[256];

static void setError(const char* message)
{
    snprintf(g_error, sizeof(g_error), "%s", message);
}

VulkanProbeResult vulkan_probe(void)
{
    VulkanProbeResult result = {0};
    g_error[0] = '\0';
    g_driverName[0] = '\0';
    result.error = g_error;
    result.driverName = g_driverName;

    if (volkInitialize() != VK_SUCCESS)
    {
        setError("volkInitialize failed");
        return result;
    }

    if (vkEnumerateInstanceVersion(&result.vulkanVersion) != VK_SUCCESS)
    {
        result.vulkanVersion = 0;
    }

    const char* enabledExtensions[1];
    uint32_t enabledExtensionCount = 0;
#if TARGET_OS_OSX || TARGET_OS_IPHONE
    enabledExtensions[enabledExtensionCount++] =
        VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME;
#endif

    const char* enabledLayers[1];
    uint32_t enabledLayerCount = 0;
#ifdef VULKAN_SWIFT_VALIDATION
    enabledLayers[enabledLayerCount++] = "VK_LAYER_KHRONOS_validation";
#endif
    result.validationEnabled = enabledLayerCount > 0 ? 1 : 0;

    const VkApplicationInfo appInfo = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "VulkanSwiftSample",
        .applicationVersion = 0,
        .pEngineName = NULL,
        .engineVersion = 0,
        .apiVersion = VK_API_VERSION_1_3,
    };

    VkInstanceCreateInfo createInfo = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &appInfo,
        .enabledLayerCount = enabledLayerCount,
        .ppEnabledLayerNames = enabledLayers,
        .enabledExtensionCount = enabledExtensionCount,
        .ppEnabledExtensionNames = enabledExtensions,
    };
#if TARGET_OS_OSX || TARGET_OS_IPHONE
    createInfo.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
#endif

    VkInstance instance = VK_NULL_HANDLE;
    VkResult resultCode = vkCreateInstance(&createInfo, NULL, &instance);
    if (resultCode != VK_SUCCESS)
    {
        char message[256];
        snprintf(message, sizeof(message), "vkCreateInstance failed: %d",
                 (int)resultCode);
        setError(message);
        return result;
    }

    volkLoadInstance(instance);

    uint32_t deviceCount = 0;
    VkResult enumResult =
        vkEnumeratePhysicalDevices(instance, &deviceCount, NULL);
    if (enumResult != VK_SUCCESS || deviceCount == 0)
    {
        setError("no physical devices");
        vkDestroyInstance(instance, NULL);
        return result;
    }

    VkPhysicalDevice device = VK_NULL_HANDLE;
    enumResult = vkEnumeratePhysicalDevices(instance, &deviceCount, &device);
    if (enumResult != VK_SUCCESS)
    {
        setError("no physical devices");
        vkDestroyInstance(instance, NULL);
        return result;
    }

    VkPhysicalDeviceDriverProperties driverProperties = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES,
    };
    VkPhysicalDeviceProperties2 properties = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
        .pNext = &driverProperties,
    };
    vkGetPhysicalDeviceProperties2(device, &properties);

    snprintf(g_driverName, sizeof(g_driverName), "%s",
             driverProperties.driverName);

    vkDestroyInstance(instance, NULL);
    return result;
}
