# Index

Read this file first when navigating the wiki.

## Sources

- [[wiki/sources/karpathy-llm-wiki]] - Source note for Andrej Karpathy's canonical `LLM Wiki` gist, the seed source for this vault.
- [[wiki/sources/obsidian-cli-help]] - Source note for Obsidian's CLI documentation, focused on vault-aware automation and inspection.

## Inspections

- [[wiki/inspections/mesa-radv-graphics-queue-family-detection]] - Traces RADV 如何判断 `vkGetPhysicalDeviceQueueFamilyProperties2` 是否 expose graphics queue family, from `radv_graphics_queue_enabled()` down to `DRM_AMDGPU_INFO` `available_rings`.
- [[wiki/inspections/mesa-radv-init-dispatch-tables-layers]] - Summarizes how `init_dispatch_tables()` builds RADV-internal device dispatch layers, including runtime-gated SQTT hooks and the non-Windows-only `rmv` layer.
- [[wiki/inspections/libdrm-amdgpu-vamgr-address-space-split]] - Explains `amdgpu_vamgr.c` GPU VA splitting into canonical `low/high` and `32-bit/rest` buckets, plus `AMDGPU_VA_RANGE_REPLAYABLE` and `va_base_required` allocation behavior.
- [[wiki/inspections/linux-dma-resv-shared-buffer-sync]] - Explains `dma_resv` as a per-buffer `ww_mutex` plus `dma_fence` container for shared, asynchronous, pipelined, and movable DMA buffers, and why not every DMA user needs it.
- [[wiki/inspections/linux-idr-preload-purpose]] - Explains `idr_preload()` as the IDR-internal node preload path used before `spin_lock()`, so `idr_alloc(..., GFP_NOWAIT)` can avoid potentially sleeping allocation in the locked section.
- [[wiki/inspections/linux-rcu-grace-period-pointer-publication]] - Explains Linux RCU as pointer publication plus deferred reclamation, grounding grace periods in `rcu_assign_pointer()`, Tree RCU `qsmask` tracking, and preempted-reader bookkeeping.

## Concepts

- None yet.

## Entities

- None yet.

## Syntheses

- [[wiki/syntheses/obsidian-cli-for-wiki-maintenance]] - Practical Obsidian CLI commands for linting links, auditing note structure, and safely refactoring the vault.

## Operational Docs

- [[AGENTS]] - The schema that defines page shapes, workflows, and commit message conventions.
- [[README]] - Repository overview and start-here instructions.
- Git history - Canonical operational history for vault changes.
