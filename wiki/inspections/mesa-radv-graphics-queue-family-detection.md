---
type: inspection
title: "How RADV 判断 vkGetPhysicalDeviceQueueFamilyProperties2 里的 graphics queue family 是否存在"
repo: mesa
repo_commit: e9d00909f5082218159541d647182176ed237e60
inspected_on: 2026-04-18
question: "RADV 是怎么判断 vkGetPhysicalDeviceQueueFamilyProperties2 应不应该 expose graphics queue family 的"
scope_paths:
  - src/amd/vulkan/radv_physical_device.c
  - src/amd/vulkan/radv_physical_device.h
  - src/amd/vulkan/winsys/amdgpu/radv_amdgpu_winsys.c
  - src/amd/vulkan/winsys/amdgpu/radv_amdgpu_winsys.h
  - src/amd/common/ac_gpu_info.c
  - src/amd/common/ac_linux_drm.c
  - src/amd/common/ac_linux_drm.h
  - src/amd/common/amd_family.h
---

## Question

RADV 是怎么判断 `vkGetPhysicalDeviceQueueFamilyProperties2` 应不应该 expose graphics queue family 的？

## Answer

`radv_GetPhysicalDeviceQueueFamilyProperties2()` 会把 queue family enumeration 交给 `radv_get_physical_device_queue_family_properties()`。这个 helper 只有在 `radv_graphics_queue_enabled(pdev)` 为 true 时，才会 count / emit graphics queue family。这个 enable check 本身非常直接：`pdev->info.ip[AMD_IP_GFX].num_queues > 0`。

在 amdgpu winsys path 上，`pdev->info` 是通过 `pdev->ws->query_info(pdev->ws, &pdev->info)` 从 winsys 缓存的 `struct radeon_info` copy 过来的。winsys 里的 `ws->info` 初始化来自 `ac_query_gpu_info()`；它会对每个 IP block call `ac_drm_query_hw_ip_info()`，读取 `struct drm_amdgpu_info_hw_ip`。在 normal ring-backed path 下，`info->ip[AMD_IP_GFX].num_queues = util_bitcount(ip_info.available_rings)`。所以，常规情况下 graphics queue family 是否存在，最终取决于 KMD 是否上报了至少一个 available GFX ring。

有一个 exception：如果 user queues 被启用，并且 `device_info.userq_ip_mask` 包含 GFX，Mesa 会直接把 `info->ip[AMD_IP_GFX].num_queues = 1`，不走 `available_rings` 的 popcount。即便如此，RADV 最终 expose 这个 family 的 predicate 仍然是同一个：`num_queues > 0`。

## Trace

1. `radv_GetPhysicalDeviceQueueFamilyProperties2()` call `radv_get_physical_device_queue_family_properties()`，先算 `pCount`，再填 `VkQueueFamilyProperties2`。
2. 这个 helper 在 count phase 和 fill phase 都会 check `radv_graphics_queue_enabled(pdev)`。
3. `radv_graphics_queue_enabled()` 没有额外 policy gate，只有 `pdev->info.ip[AMD_IP_GFX].num_queues > 0`。
4. 如果 condition 成立，RADV 会 expose 一个 graphics-capable Vulkan queue family，flags 是 `VK_QUEUE_GRAPHICS_BIT | VK_QUEUE_COMPUTE_BIT | VK_QUEUE_TRANSFER_BIT | VK_QUEUE_SPARSE_BINDING_BIT`，并且 `queueCount = 1`。
5. `struct radv_physical_device` 把这份 state 存在 `struct radeon_info info` 里；初始化发生在 `pdev->ws->query_info(pdev->ws, &pdev->info)`。
6. 在 amdgpu winsys implementation 里，`radv_amdgpu_winsys_query_info()` 只是把 `ws->info` copy 给 caller。
7. `ws->info` 更早是在 winsys create path 里通过 `ac_query_gpu_info(fd, ws->dev, &ws->info, true)` 填充的。
8. `ac_query_gpu_info()` 会 iterate 所有 `ip_type`，对每个 IP call `ac_drm_query_hw_ip_info(dev, ip_type, 0, &ip_info)`，然后决定 `info->ip[ip_type].num_queues`。
9. `AMD_IP_GFX` 就是 graphics IP type；Mesa 还用 `STATIC_ASSERT(AMDGPU_HW_IP_GFX == AMD_IP_GFX)` 保证 userspace / kernel 的 enum 对齐。
10. `ac_drm_query_hw_ip_info()` 通过 `DRM_AMDGPU_INFO` ioctl、`query = AMDGPU_INFO_HW_IP_INFO` 向 KMD 取 `drm_amdgpu_info_hw_ip`。
11. 在 normal path 下，`info->ip[AMD_IP_GFX].num_queues = util_bitcount(ip_info.available_rings)`；也就是 available GFX rings 的 bit popcount。

## Evidence

- `src/amd/vulkan/radv_physical_device.c:2720-2733`：`radv_GetPhysicalDeviceQueueFamilyProperties2()` 把 enumeration 交给 `radv_get_physical_device_queue_family_properties()`。
- `src/amd/vulkan/radv_physical_device.c:2590-2637`：只有在 `radv_graphics_queue_enabled(pdev)` 为 true 时，graphics family 才会被 count / emit；这个 family 的 `queueCount = 1`。
- `src/amd/vulkan/radv_physical_device.c:127-130`：`radv_graphics_queue_enabled()` 就是 `pdev->info.ip[AMD_IP_GFX].num_queues > 0`。
- `src/amd/vulkan/radv_physical_device.c:2293-2296`：`pdev->info` 通过 `pdev->ws->query_info(pdev->ws, &pdev->info)` 初始化。
- `src/amd/vulkan/radv_physical_device.h:99-104`：`pdev->info` 的类型是 `struct radeon_info`。
- `src/amd/vulkan/winsys/amdgpu/radv_amdgpu_winsys.c:26-29`：`radv_amdgpu_winsys_query_info()` 只是把 `ws->info` copy 出去。
- `src/amd/vulkan/winsys/amdgpu/radv_amdgpu_winsys.c:276-277,333`：`ws->info` 来自 `ac_query_gpu_info()`，并通过 `ws->base.query_info` 暴露给上层。
- `src/amd/vulkan/winsys/amdgpu/radv_amdgpu_winsys.h:24-30`：amdgpu winsys 缓存 GPU state 的字段就是 `struct radeon_info info`。
- `src/amd/common/ac_gpu_info.c:302-320`：`info->ip[ip_type].num_queues` 要么在 userq path 被直接设成 `1`，要么在 normal path 里设成 `util_bitcount(ip_info.available_rings)`。
- `src/amd/common/ac_gpu_info.c:257-264`：Mesa 用 `STATIC_ASSERT` 保证 kernel `AMDGPU_HW_IP_*` 和 userspace `AMD_IP_*` 的 enum 一一对应。
- `src/amd/common/amd_family.h:159-163`：`AMD_IP_GFX` 是 graphics IP enum entry。
- `src/amd/common/ac_linux_drm.c:605-621`：`ac_drm_query_hw_ip_info()` 通过 `DRM_AMDGPU_INFO` + `AMDGPU_INFO_HW_IP_INFO` 向 KMD query HW IP info。
- `src/amd/common/ac_linux_drm.h:190-197`：`struct drm_amdgpu_info_hw_ip` 里定义了 `available_rings`。

## Uncertainty

None noted.

## Related Pages

- [[wiki/index]]
