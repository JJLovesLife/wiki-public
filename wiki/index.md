# Index

Read this file first when navigating the wiki.

## Sources

- [[wiki/sources/intel-lga1700-learning-notes]] - Source note for jjshao's Intel LGA 1700 and open X86 motherboard learning notes, covering socket signal groups, CPU/PCH routing, memory pins, and CPU power sense observations.
- [[wiki/sources/karpathy-llm-wiki]] - Source note for Andrej Karpathy's canonical `LLM Wiki` gist, the seed source for this vault.
- [[wiki/sources/obsidian-cli-help]] - Source note for Obsidian's CLI documentation, focused on vault-aware automation and inspection.

## Inspections

- [[wiki/inspections/mesa-radv-graphics-queue-family-detection]] - Traces RADV 如何判断 `vkGetPhysicalDeviceQueueFamilyProperties2` 是否 expose graphics queue family, from `radv_graphics_queue_enabled()` down to `DRM_AMDGPU_INFO` `available_rings`.
- [[wiki/inspections/mesa-radv-init-dispatch-tables-layers]] - Summarizes how `init_dispatch_tables()` builds RADV-internal device dispatch layers, including runtime-gated SQTT hooks and the non-Windows-only `rmv` layer.
- [[wiki/inspections/libdrm-amdgpu-vamgr-address-space-split]] - Explains `amdgpu_vamgr.c` GPU VA splitting into canonical `low/high` and `32-bit/rest` buckets, plus `AMDGPU_VA_RANGE_REPLAYABLE` and `va_base_required` allocation behavior.
- [[wiki/inspections/linux-amdgpu-eviction-fence-userq-bo-move]] - Explains how amdgpu uses per-file eviction fences on BO `dma_resv` objects to create a user queue quiescent point before TTM/VM BO moves or validation proceed.
- [[wiki/inspections/linux-amdgpu-userq-bo-mmap-vs-eviction-manager]] - Contrasts CPU mmap BO synchronization via zap-and-refault with user queue BO GPU VA references that require eviction-manager quiescence before BO moves.
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]] - Explains `dma_resv` as a per-buffer `ww_mutex` plus `dma_fence` container for shared, asynchronous, pipelined, and movable DMA buffers, and why not every DMA user needs it.
- [[wiki/inspections/linux-idr-preload-purpose]] - Explains `idr_preload()` as the IDR-internal node preload path used before `spin_lock()`, so `idr_alloc(..., GFP_NOWAIT)` can avoid potentially sleeping allocation in the locked section.
- [[wiki/inspections/linux-rcu-grace-period-pointer-publication]] - Explains Linux RCU as pointer publication plus deferred reclamation, grounding grace periods in `rcu_assign_pointer()`, Tree RCU `qsmask` tracking, and preempted-reader bookkeeping.
- [[wiki/inspections/linux-rcu-child-reference-lifetime]] - Summarizes how RCU-published lookup structures can safely expose refcounted child objects, using `dma_resv_list` and `dma_fence` to show when immediate child `put` is safe.

## Concepts

- [[wiki/concepts/cpu-sense-pins-kelvin-remote-voltage-sense]] - Explains CPU `_SENSE` pins as Kelvin-connected remote voltage sense points measured by the VR controller, including VCCIN_AUX synchronous buck feedback and VCC/VSS open-circuit protection behavior.
- [[wiki/concepts/intel-lga1700-socket-signal-groups]] - Organizes Intel LGA 1700 socket pins into power/GND, CPU-PCH, PCIe, DDI, DDR memory, debug, and platform-control signal groups.
- [[wiki/concepts/drm-mm]] - Explains `drm_mm` as DRM's caller-owned-node range allocator for abstract address spaces and placement ranges.
- [[wiki/concepts/drm-vma-offset]] - Explains `drm_vma_offset` as the fake mmap offset-to-BO mapping layer built on `drm_mm`, including per-file access checks and the per-device namespace uncertainty.
- [[wiki/concepts/opencode-usage-tips]] - Collects practical OpenCode usage tips, including observed active-file context behavior not covered by official docs.

## Entities

- None yet.

## Syntheses

- [[wiki/syntheses/obsidian-cli-for-wiki-maintenance]] - Practical Obsidian CLI commands for linting links, auditing note structure, and safely refactoring the vault.

## Operational Docs

- [[AGENTS]] - The schema that defines page shapes, workflows, and commit message conventions.
- [[README]] - Repository overview and start-here instructions.
- Git history - Canonical operational history for vault changes.
