// Bend 2.0.37 effect ABI. Only the IO event loop accesses the registry.
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <limits.h>
#include <math.h>

#if !defined(__linux__) || UINTPTR_MAX != UINT64_MAX
#error "bend-vulkan currently requires 64-bit Linux"
#endif

#define BV_INVALID 0x60000002u
#define BV_ARGUMENT 0x60000003u
#define BV_LIFETIME 0x60000004u
#define BV_LIMIT 0x60000005u
#define BV_MAX_COPY (16u * 1024u * 1024u)

typedef enum { BV_ENTRY, BV_INSTANCE, BV_PHYSICAL, BV_DEVICE, BV_BUFFER,
  BV_MEMORY, BV_POOL, BV_COMMAND, BV_FENCE, BV_IMAGE, BV_IMAGE_VIEW, BV_RENDER_PASS, BV_FRAMEBUFFER } BvKind;
typedef struct BvRow BvRow;
typedef enum { BV_INITIAL, BV_RECORDING, BV_EXECUTABLE, BV_PENDING, BV_UNCERTAIN, BV_COMPLETED, BV_COMMAND_INVALID } BvCommandPhase;
typedef enum { BV_OUTSIDE, BV_INSIDE } BvRenderTag;
typedef struct { BvRenderTag tag; union { struct { BvRow* framebuffer; } inside; } data; } BvRenderScope;
typedef struct {
  BvCommandPhase phase;
  union { struct { BvRenderScope scope; } recording; struct { BvRow* fence; } pending; struct { BvRow* fence; } uncertain; } submission;
} BvCommand;
typedef enum { BV_CALLER, BV_CONVENIENCE_PRIVATE } BvFenceLifetime;
typedef struct { BvFenceLifetime lifetime; } BvFence;
typedef enum { BV_HEALTHY, BV_LOST } BvHealth;
typedef enum { BV_DEP_RECORDED, BV_DEP_BINDING, BV_DEP_VIEW_IMAGE,
  BV_DEP_FRAMEBUFFER_PASS, BV_DEP_FRAMEBUFFER_VIEW } BvDepRole;
typedef struct BvDep {
  BvRow* target;
  BvDepRole role;
  uint64_t offset;
  struct BvDep* next;
} BvDep;
typedef struct { VkFormat format; VkExtent2D extent; uint32_t mips,layers; VkImageUsageFlags usage; } BvImage;
typedef struct { VkImageViewType type; VkImageSubresourceRange range; } BvImageView;
typedef struct { uint32_t colors,count; VkAttachmentDescription* attachments; } BvRenderPass;
typedef struct { VkExtent2D extent; uint32_t count; BvDep** attachments; } BvFramebuffer;
struct BvRow {
  uint32_t id;
  BvKind kind;
  BvRow *parent, *next;
  uint64_t handle, size;
  VkMemoryRequirements requirements;
  uint32_t flags, memory_type;
  union { BvImage image; BvImageView view; BvRenderPass pass; BvFramebuffer framebuffer; } object;
  BvCommand command;
  BvFence fence;
  void* context;
  BvDep* deps;
};
static BvRow* bv_rows;
static uint32_t bv_next_id = 1;

typedef struct {
  void* library;
  PFN_vkGetInstanceProcAddr get;
  PFN_vkCreateInstance create;
  PFN_vkEnumerateInstanceVersion version;
  PFN_vkEnumerateInstanceLayerProperties layers;
  PFN_vkEnumerateInstanceExtensionProperties extensions;
} BvEntry;

typedef struct {
  VkInstance handle;
  PFN_vkDestroyInstance destroy;
  PFN_vkEnumeratePhysicalDevices enumerate;
  PFN_vkGetPhysicalDeviceProperties properties;
  PFN_vkGetPhysicalDeviceQueueFamilyProperties queues;
  PFN_vkGetPhysicalDeviceMemoryProperties memory;
  PFN_vkEnumerateDeviceExtensionProperties extensions;
  PFN_vkGetPhysicalDeviceFormatProperties formats;
  PFN_vkGetPhysicalDeviceImageFormatProperties image_formats;
  PFN_vkCreateDevice create_device;
  PFN_vkGetDeviceProcAddr get_device;
} BvInstance;

#define BV_DEVICE_FUNCTIONS(X) \
  X(DestroyDevice) X(DeviceWaitIdle) X(GetDeviceQueue) \
  X(CreateBuffer) X(DestroyBuffer) X(GetBufferMemoryRequirements) \
  X(CreateImage) X(DestroyImage) X(GetImageMemoryRequirements) X(BindImageMemory) \
  X(CreateImageView) X(DestroyImageView) \
  X(CreateRenderPass) X(DestroyRenderPass) X(CreateFramebuffer) X(DestroyFramebuffer) \
  X(CmdBeginRenderPass) X(CmdEndRenderPass) \
  X(AllocateMemory) X(FreeMemory) X(BindBufferMemory) X(MapMemory) X(UnmapMemory) \
  X(FlushMappedMemoryRanges) X(InvalidateMappedMemoryRanges) \
  X(CreateCommandPool) X(DestroyCommandPool) X(AllocateCommandBuffers) \
  X(BeginCommandBuffer) X(EndCommandBuffer) X(CmdFillBuffer) \
  X(CmdClearColorImage) X(CmdClearDepthStencilImage) X(CmdCopyBufferToImage) X(CmdCopyImageToBuffer) \
  X(CmdCopyBuffer) X(CmdPipelineBarrier) X(QueueSubmit) \
  X(CreateFence) X(DestroyFence) X(GetFenceStatus) X(WaitForFences) X(ResetFences) X(ResetCommandBuffer)
typedef struct {
  VkDevice handle;
  BvHealth health;
  BvRow* convenience;
  VkPhysicalDevice physical;
  VkQueue queue;
  uint32_t family, queue_flags;
  VkQueueFamilyProperties queue_properties;
  VkPhysicalDeviceLimits limits;
  VkPhysicalDeviceMemoryProperties memory;
#define BV_FIELD(name) PFN_vk##name name;
  BV_DEVICE_FUNCTIONS(BV_FIELD)
#undef BV_FIELD
} BvDevice;

static void bv_unpack(Env e, Term value, uint32_t count, Term* fields) {
  spare_free(e, cls_fit(count), ctr_take(e, value, count, fields));
}
static uint32_t bv_key(Env e, Term value) {
  if (term_tag(value) == TAG_PAK) return (uint32_t)term_loc(value);
  Term fields[1]; bv_unpack(e, value, 1, fields); return (uint32_t)fields[0];
}
static uint64_t bv_u64(Env e, Term value) {
  Term fields[2]; bv_unpack(e, value, 2, fields);
  return ((uint64_t)(uint32_t)fields[1] << 32) | (uint32_t)fields[0];
}
static Term bv_words(Env e, uint64_t value) {
  return io_tup(e, (uint32_t)value, (uint32_t)(value >> 32));
}
static Term bv_node(Env e, uint64_t cid, uint32_t count, Term* fields) {
  uint64_t location = heap_alloc(e, cls_fit(count));
  for (uint32_t j = 0; j < count; j++) e.mem[location+j] = io_seal(e, fields[j], cid);
  return term_ctr(cid, location);
}
static Term bv_ok(Env e) { return io_done(e, term_pak(CID(Unit), 0)); }
static Term bv_vk_error(Env e, VkResult result, const char* operation) {
  char message[192];
  snprintf(message, sizeof(message), "%s: VkResult %d", operation, (int)result);
  return io_fail(e, (uint32_t)(int32_t)result, message);
}
static BvRow* bv_get(uint32_t id, BvKind kind) {
  for (BvRow* row = bv_rows; row; row = row->next)
    if (row->id == id) return row->kind == kind ? row : NULL;
  return NULL;
}
static BvRow* bv_add(BvKind kind, BvRow* parent) {
  // Keys never repeat, including after a failed creation or a freed row.
  if (!bv_next_id) return NULL;
  BvRow* row = calloc(1, sizeof(*row));
  if (!row) return NULL;
  row->id = bv_next_id++; row->kind = kind; row->parent = parent;
  row->next = bv_rows; bv_rows = row;
  return row;
}
static void bv_remove(BvRow* row) {
  BvRow** link = &bv_rows;
  while (*link != row) link = &(*link)->next;
  *link = row->next;
  while (row->deps) { BvDep* use = row->deps; row->deps = use->next; free(use); }
  if (row->kind==BV_RENDER_PASS) free(row->object.pass.attachments);
  if (row->kind==BV_FRAMEBUFFER) free(row->object.framebuffer.attachments);
  free(row);
}
static BvRow* bv_child(uint32_t id, BvKind kind, BvRow* owner) {
  BvRow* row = bv_get(id, kind);
  return row && row->parent == owner ? row : NULL;
}
static BvRow* bv_command_device(BvRow* command) {
  return command ? command->parent->parent : NULL;
}
static int bv_outside(const BvRow* command) {
  return command->command.phase==BV_RECORDING && command->command.submission.recording.scope.tag==BV_OUTSIDE;
}
static BvRow* bv_command_fence(BvRow* command) {
  if (command->command.phase==BV_PENDING) return command->command.submission.pending.fence;
  if (command->command.phase==BV_UNCERTAIN) return command->command.submission.uncertain.fence;
  return NULL;
}
static BvRow* bv_active(BvRow* owner,BvRow* fence) {
  for (BvRow* row=bv_rows;row;row=row->next)
    if (row->kind==BV_COMMAND && bv_command_device(row)==owner && bv_command_fence(row) &&
        (!fence || bv_command_fence(row)==fence)) return row;
  return NULL;
}
static void bv_complete(BvRow* command) {
  command->command.phase=command->command.phase==BV_PENDING ? BV_COMPLETED : BV_COMMAND_INVALID;
  memset(&command->command.submission,0,sizeof(command->command.submission));
}
static VkResult bv_device_result(BvRow* owner,VkResult result) {
  BvDevice* device=owner->context;
  if (result==VK_ERROR_DEVICE_LOST) {
    device->health=BV_LOST;
    for (BvRow* row=bv_rows;row;row=row->next)
      if (row->kind==BV_COMMAND && bv_command_device(row)==owner) {
        row->command.phase=BV_COMMAND_INVALID;
        memset(&row->command.submission,0,sizeof(row->command.submission));
      }
  }
  return result;
}
static Term bv_device_error(Env e,BvRow* owner,VkResult result,const char* operation) {
  return bv_vk_error(e,bv_device_result(owner,result),operation);
}
static int bv_lost(BvRow* owner) { return ((BvDevice*)owner->context)->health==BV_LOST; }
static VkResult bv_idle(BvRow* owner) {
  if (bv_lost(owner)) return VK_ERROR_DEVICE_LOST;
  BvDevice* device=owner->context;
  VkResult result=bv_device_result(owner,device->DeviceWaitIdle(device->handle));
  if (result==VK_SUCCESS) {
    BvRow* command=bv_active(owner,NULL);
    if (command) bv_complete(command);
  }
  return result;
}
static BvDep* bv_dependency(const BvRow* row,BvDepRole role) {
  for (BvDep* dep=row->deps;dep;dep=dep->next) if (dep->role==role) return dep;
  return NULL;
}
static BvRow* bv_bound_memory(const BvRow* row) {
  BvDep* binding=bv_dependency(row,BV_DEP_BINDING);
  return binding ? binding->target : NULL;
}
static uint64_t bv_bound_offset(const BvRow* row) {
  return bv_dependency(row,BV_DEP_BINDING)->offset;
}
static int bv_reaches_depth(const BvRow* row,const BvRow* target,unsigned remaining) {
  if (row==target) return 1;
  if (!remaining) return 0;
  for (BvDep* dep=row->deps;dep;dep=dep->next)
    if (bv_reaches_depth(dep->target,target,remaining-1)) return 1;
  return 0;
}
static int bv_memory_busy(BvRow* memory) {
  BvRow* command=bv_active(memory->parent,NULL);
  return command && bv_reaches_depth(command,memory,4);
}
static BvRow* bv_public_fence(uint32_t id) {
  BvRow* fence=bv_get(id,BV_FENCE);
  return fence && fence->fence.lifetime==BV_CALLER ? fence : NULL;
}
static int bv_referenced(BvRow* buffer) {
  for (BvRow* row = bv_rows; row; row = row->next)
    for (BvDep* use = row->deps; use; use = use->next)
      if (use->target == buffer) return 1;
  return 0;
}
static void bv_free_refs(BvDep* uses) {
  while (uses) { BvDep* next=uses->next; free(uses); uses=next; }
}
static int bv_prepare_refs(BvRow* command, uint32_t count, BvRow** resources) {
  BvDep* staged=NULL;
  for (uint32_t j=0;j<count;j++) {
    int found=0;
    for (BvDep* u=command->deps;u;u=u->next) found |= u->target==resources[j];
    for (BvDep* u=staged;u;u=u->next) found |= u->target==resources[j];
    if (found) continue;
    BvDep* use=malloc(sizeof(*use));
    if (!use) { bv_free_refs(staged); return 0; }
    use->target=resources[j]; use->role=BV_DEP_RECORDED; use->offset=0; use->next=staged; staged=use;
  }
  while (staged) {
    BvDep* next=staged->next; staged->next=command->deps; command->deps=staged; staged=next;
  }
  return 1;
}

static uint32_t bv_baseline_stages(BvDevice* device, uint32_t mask) {
  const uint32_t baseline_graphics=VK_PIPELINE_STAGE_VERTEX_INPUT_BIT|VK_PIPELINE_STAGE_VERTEX_SHADER_BIT|
    VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT|VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT|
    VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT|VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  uint32_t allowed=VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT|VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT|VK_PIPELINE_STAGE_HOST_BIT;
  if (device->queue_flags & VK_QUEUE_GRAPHICS_BIT) allowed |= baseline_graphics;
  if (device->queue_flags & VK_QUEUE_COMPUTE_BIT) allowed |= VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
  if (device->queue_flags & (VK_QUEUE_GRAPHICS_BIT|VK_QUEUE_COMPUTE_BIT)) allowed |= VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT;
  if (device->queue_flags & (VK_QUEUE_GRAPHICS_BIT|VK_QUEUE_COMPUTE_BIT|VK_QUEUE_TRANSFER_BIT)) allowed |= VK_PIPELINE_STAGE_TRANSFER_BIT;
  if (!mask || (mask & ~(allowed|VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT|VK_PIPELINE_STAGE_ALL_COMMANDS_BIT))) return 0;
  uint32_t expanded=mask & allowed;
  if (mask & VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT) {
    if (!(device->queue_flags & VK_QUEUE_GRAPHICS_BIT)) return 0;
    expanded |= baseline_graphics|VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT;
  }
  if (mask & VK_PIPELINE_STAGE_ALL_COMMANDS_BIT) expanded |= allowed & ~VK_PIPELINE_STAGE_HOST_BIT;
  return expanded;
}
static int bv_access(uint32_t stages, uint32_t access) {
  const uint32_t shaders=VK_PIPELINE_STAGE_VERTEX_SHADER_BIT|VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT|VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
  static const struct { uint32_t access, stages; } table[]={
    {VK_ACCESS_INDIRECT_COMMAND_READ_BIT,VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT},
    {VK_ACCESS_INDEX_READ_BIT|VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT,VK_PIPELINE_STAGE_VERTEX_INPUT_BIT},
    {VK_ACCESS_UNIFORM_READ_BIT|VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT,0},
    {VK_ACCESS_INPUT_ATTACHMENT_READ_BIT,VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT},
    {VK_ACCESS_COLOR_ATTACHMENT_READ_BIT|VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT},
    {VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT|VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT|VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT},
    {VK_ACCESS_TRANSFER_READ_BIT|VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT},
    {VK_ACCESS_HOST_READ_BIT|VK_ACCESS_HOST_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT},
    {VK_ACCESS_MEMORY_READ_BIT|VK_ACCESS_MEMORY_WRITE_BIT,UINT32_MAX}
  };
  uint32_t supported=0;
  for (size_t j=0;j<sizeof(table)/sizeof(*table);j++)
    if (stages & (table[j].stages ? table[j].stages : shaders)) supported |= table[j].access;
  return !(access & ~supported);
}
static int bv_has_children(BvRow* parent, BvKind ignored) {
  for (BvRow* row = bv_rows; row; row = row->next)
    if (row->parent == parent && row->kind != ignored) return 1;
  return 0;
}
static void bv_destroy_pool(BvRow* pool) {
  BvDevice* device = pool->parent->context;
  device->DestroyCommandPool(device->handle, (VkCommandPool)(uintptr_t)pool->handle, NULL);
  for (BvRow* row = bv_rows, *next; row; row = next) {
    next = row->next;
    if (row->parent == pool) bv_remove(row);
  }
  bv_remove(pool);
}
static void bv_destroy_device(BvRow* row) {
  BvDevice* device = row->context;
  for (;;) {
    BvRow* pool = NULL;
    for (BvRow* child = bv_rows; child; child = child->next)
      if (child->parent == row && child->kind == BV_POOL) { pool = child; break; }
    if (!pool) break;
    bv_destroy_pool(pool);
  }
  for (BvRow* child=bv_rows,*next;child;child=next) {
    next=child->next;
    if (child->parent==row && child->kind==BV_FENCE) {
      device->DestroyFence(device->handle,(VkFence)(uintptr_t)child->handle,NULL);bv_remove(child);
    }
  }
  device->convenience=NULL;
  const BvKind order[]={BV_FRAMEBUFFER,BV_IMAGE_VIEW,BV_RENDER_PASS,BV_IMAGE,BV_BUFFER};
  for (unsigned j=0;j<sizeof(order)/sizeof(*order);j++)
    for (BvRow* child=bv_rows,*next;child;child=next) {
      next=child->next;
      if (child->parent!=row || child->kind!=order[j]) continue;
      if (child->kind==BV_FRAMEBUFFER) device->DestroyFramebuffer(device->handle,(VkFramebuffer)(uintptr_t)child->handle,NULL);
      else if (child->kind==BV_RENDER_PASS) device->DestroyRenderPass(device->handle,(VkRenderPass)(uintptr_t)child->handle,NULL);
      else if (child->kind==BV_IMAGE_VIEW) device->DestroyImageView(device->handle,(VkImageView)(uintptr_t)child->handle,NULL);
      else if (child->kind==BV_IMAGE) device->DestroyImage(device->handle,(VkImage)(uintptr_t)child->handle,NULL);
      else device->DestroyBuffer(device->handle,(VkBuffer)(uintptr_t)child->handle,NULL);
      bv_remove(child);
    }
  for (BvRow* child = bv_rows, *next; child; child = next) {
    next = child->next;
    if (child->parent == row && child->kind == BV_MEMORY) {
      device->FreeMemory(device->handle, (VkDeviceMemory)(uintptr_t)child->handle, NULL);
      bv_remove(child);
    }
  }
  device->DestroyDevice(device->handle, NULL); free(device); bv_remove(row);
}
static void bv_destroy_instance(BvRow* row) {
  BvInstance* instance = row->context;
  for (BvRow* child = bv_rows, *next; child; child = next) {
    next = child->next;
    if (child->parent == row && child->kind == BV_PHYSICAL) bv_remove(child);
  }
  instance->destroy(instance->handle, NULL); free(instance); bv_remove(row);
}

// Marshal string arrays for Vk*CreateInfo. Every failure still consumes the input.
typedef struct { char** values; uint32_t count; int valid; } BvNames;
static BvNames bv_names(Env e, Term list) {
  BvNames names = {NULL, 0, 1};
#ifdef CID(Con)
  while (term_aux(list) == CID(Con)) {
    Term fields[2]; bv_unpack(e, list, 2, fields); list = fields[1];
    uint64_t length = 0; char* text = io_cstr(e, fields[0], &length);
    if (io_nul(text, length) || names.count >= 1024) names.valid = 0;
    char** more = realloc(names.values, (names.count+1)*sizeof(char*));
    if (!more) { free(text); term_sink(e, list); names.valid = 0; break; }
    names.values = more; names.values[names.count++] = text;
  }
#endif
  return names;
}
static void bv_names_free(BvNames names) {
  for (uint32_t j = 0; j < names.count; j++) free(names.values[j]);
  free(names.values);
}

#ifdef CID(Entry.load)
static Term bv_entry_load(Env e, Term* f, IoWork* w) {
  void* library = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
  if (!library) return io_fail(e, 0x60000001u, dlerror());
  BvEntry* entry = calloc(1, sizeof(*entry));
  BvRow* row = entry ? bv_add(BV_ENTRY, NULL) : NULL;
  if (!row) { free(entry); dlclose(library); return io_fail(e, BV_LIMIT, "registry allocation failed"); }
  entry->library = library;
  entry->get = (PFN_vkGetInstanceProcAddr)dlsym(library, "vkGetInstanceProcAddr");
  if (entry->get) {
    entry->create = (PFN_vkCreateInstance)entry->get(VK_NULL_HANDLE, "vkCreateInstance");
    entry->version = (PFN_vkEnumerateInstanceVersion)entry->get(VK_NULL_HANDLE, "vkEnumerateInstanceVersion");
    entry->layers = (PFN_vkEnumerateInstanceLayerProperties)entry->get(VK_NULL_HANDLE, "vkEnumerateInstanceLayerProperties");
    entry->extensions = (PFN_vkEnumerateInstanceExtensionProperties)entry->get(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties");
  }
  if (!entry->get || !entry->create || !entry->layers || !entry->extensions) {
    bv_remove(row); free(entry); dlclose(library);
    return io_fail(e, 0x60000001u, "missing Vulkan loader entry points");
  }
  row->context = entry;
  return io_done(e, term_pak(CID(Entry),row->id));
}
#endif
#ifdef CID(Entry.close)
static Term bv_entry_close(Env e, Term* f, IoWork* w) {
  BvRow* entry = bv_get(bv_key(e, f[0]), BV_ENTRY);
  if (!entry) return io_fail(e, BV_INVALID, "Entry.close: invalid entry");
  VkResult first = VK_SUCCESS;
  for (;;) {
    BvRow* found = NULL;
    for (BvRow* row = bv_rows; row; row = row->next)
      if (row->kind == BV_DEVICE && row->parent->parent == entry) { found = row; break; }
    if (!found) break;
    VkResult result = bv_idle(found);
    if (result != VK_SUCCESS && result != VK_ERROR_DEVICE_LOST)
      return bv_vk_error(e, result, "Entry.close / vkDeviceWaitIdle (entry remains live)");
    if (first == VK_SUCCESS && result != VK_SUCCESS) first = result;
    bv_destroy_device(found);
  }
  for (;;) {
    BvRow* found = NULL;
    for (BvRow* row = bv_rows; row; row = row->next)
      if (row->kind == BV_INSTANCE && row->parent == entry) { found = row; break; }
    if (!found) break;
    bv_destroy_instance(found);
  }
  BvEntry* context = entry->context;
  dlclose(context->library); free(context); bv_remove(entry);
  return first == VK_SUCCESS ? bv_ok(e) : bv_vk_error(e, first, "Entry.close / vkDeviceWaitIdle");
}
#endif
#ifdef CID(Entry.enumerate_instance_version)
static Term bv_entry_version(Env e, Term* f, IoWork* w) {
  BvRow* row = bv_get(bv_key(e, f[0]), BV_ENTRY);
  if (!row) return io_fail(e, BV_INVALID, "invalid entry");
  BvEntry* entry = row->context; uint32_t version = VK_API_VERSION_1_0;
  VkResult result = entry->version ? entry->version(&version) : VK_SUCCESS;
  return result == VK_SUCCESS ? io_done(e, version) : bv_vk_error(e, result, "vkEnumerateInstanceVersion");
}
#endif
#ifdef CID(Entry.create_instance)
static Term bv_create_instance(Env e, Term* f, IoWork* w) {
  BvRow* owner = bv_get(bv_key(e, f[0]), BV_ENTRY);
  Term info[4]; bv_unpack(e, f[1], 4, info);
  uint64_t length = 0; char* app = io_cstr(e, info[0], &length);
  BvNames layers = bv_names(e, info[2]), extensions = bv_names(e, info[3]);
  int valid = owner && !io_nul(app, length) && layers.valid && extensions.valid;
  VkInstance handle = VK_NULL_HANDLE; VkResult result = VK_SUCCESS;
  if (valid) {
    VkApplicationInfo application = {.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,
      .pApplicationName=app, .pEngineName="Bend", .apiVersion=(uint32_t)info[1]};
    VkInstanceCreateInfo create = {.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
      .pApplicationInfo=&application, .enabledLayerCount=layers.count,
      .ppEnabledLayerNames=(const char* const*)layers.values,
      .enabledExtensionCount=extensions.count,
      .ppEnabledExtensionNames=(const char* const*)extensions.values};
    BvEntry* entry = owner->context; result = entry->create(&create, NULL, &handle);
  }
  free(app); bv_names_free(layers); bv_names_free(extensions);
  if (!valid) return io_fail(e, owner ? BV_ARGUMENT : BV_INVALID, "invalid entry or instance strings");
  if (result != VK_SUCCESS) return bv_vk_error(e, result, "vkCreateInstance");
  BvEntry* entry = owner->context;
  BvInstance* instance = calloc(1, sizeof(*instance));
  PFN_vkDestroyInstance destroy = (PFN_vkDestroyInstance)entry->get(handle, "vkDestroyInstance");
  if (!instance) { destroy(handle, NULL); return io_fail(e, BV_LIMIT, "instance allocation failed"); }
  instance->handle=handle; instance->destroy=destroy;
#define BV_INSTANCE_LOAD(field, name) instance->field=(PFN_vk##name)entry->get(handle, "vk" #name)
  BV_INSTANCE_LOAD(enumerate, EnumeratePhysicalDevices);
  BV_INSTANCE_LOAD(properties, GetPhysicalDeviceProperties);
  BV_INSTANCE_LOAD(queues, GetPhysicalDeviceQueueFamilyProperties);
  BV_INSTANCE_LOAD(memory, GetPhysicalDeviceMemoryProperties);
  BV_INSTANCE_LOAD(extensions, EnumerateDeviceExtensionProperties);
  BV_INSTANCE_LOAD(formats, GetPhysicalDeviceFormatProperties);
  BV_INSTANCE_LOAD(image_formats, GetPhysicalDeviceImageFormatProperties);
  BV_INSTANCE_LOAD(create_device, CreateDevice);
  BV_INSTANCE_LOAD(get_device, GetDeviceProcAddr);
#undef BV_INSTANCE_LOAD
  BvRow* row = NULL;
  if (destroy && instance->enumerate && instance->properties && instance->queues &&
      instance->memory && instance->extensions && instance->formats && instance->image_formats && instance->create_device && instance->get_device) row=bv_add(BV_INSTANCE, owner);
  if (!row) { if (destroy) destroy(handle,NULL); free(instance); return io_fail(e,BV_LIMIT,"instance dispatch unavailable"); }
  row->context=instance; row->handle=(uint64_t)(uintptr_t)handle;
  return io_done(e,term_pak(CID(Instance),row->id));
}
#endif
#ifdef CID(Instance.destroy)
static Term bv_destroy_instance_effect(Env e, Term* f, IoWork* w) {
  BvRow* row = bv_get(bv_key(e,f[0]),BV_INSTANCE);
  if (!row) return io_fail(e,BV_INVALID,"invalid instance");
  if (bv_has_children(row,BV_PHYSICAL)) return io_fail(e,BV_LIFETIME,"instance still has devices");
  bv_destroy_instance(row); return bv_ok(e);
}
#endif
#ifdef CID(Instance.enumerate_physical_devices)
static Term bv_enumerate_physical_devices(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE);
  if (!owner) return io_fail(e,BV_INVALID,"invalid instance");
  BvInstance* instance=owner->context; VkPhysicalDevice* devices=NULL; uint32_t count=0;
  VkResult result=VK_INCOMPLETE;
  for (unsigned retry=0; retry<8 && result==VK_INCOMPLETE; retry++) {
    free(devices); devices=NULL;
    result=instance->enumerate(instance->handle,&count,NULL);
    if (result!=VK_SUCCESS && result!=VK_INCOMPLETE) break;
    if (!count) {result=VK_SUCCESS;break;}
    if (count>4096) {free(devices);return io_fail(e,BV_LIMIT,"too many physical devices");}
    devices=calloc(count,sizeof(*devices));
    if (!devices) return io_fail(e,BV_LIMIT,"enumeration allocation failed");
    result=instance->enumerate(instance->handle,&count,devices);
  }
  if (result!=VK_SUCCESS) {free(devices);return bv_vk_error(e,result,"vkEnumeratePhysicalDevices");}
  Term list=term_pak(CID(Nil),0);
  for (uint32_t j=count;j>0;j--) {
    BvRow* row=NULL;
    for (BvRow* r=bv_rows;r;r=r->next)
      if (r->kind==BV_PHYSICAL && r->parent==owner && r->handle==(uint64_t)(uintptr_t)devices[j-1]) {row=r;break;}
    if (!row) row=bv_add(BV_PHYSICAL,owner);
    if (!row) {free(devices);term_sink(e,list);return io_fail(e,BV_LIMIT,"physical-device registry full");}
    row->handle=(uint64_t)(uintptr_t)devices[j-1];
    list=io_node(e,CID(Con),term_pak(CID(PhysicalDevice),row->id),list);
  }
  free(devices);return io_done(e,list);
}
#endif
#ifdef CID(Instance.get_physical_device_properties)
static Term bv_physical_properties(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE);
  BvRow* physical=bv_child(bv_key(e,f[1]),BV_PHYSICAL,owner);
  if (!owner || !physical) return io_fail(e,BV_INVALID,"invalid physical device or instance");
  BvInstance* instance=owner->context;VkPhysicalDeviceProperties properties;
  instance->properties((VkPhysicalDevice)(uintptr_t)physical->handle,&properties);
  Term fields[]={io_str(e,properties.deviceName,strlen(properties.deviceName)), properties.apiVersion,
    properties.driverVersion,properties.vendorID,properties.deviceID,properties.deviceType};
  return io_done(e,bv_node(e,CID(PhysicalDeviceProperties),6,fields));
}
#endif
#ifdef CID(Instance.get_physical_device_queue_family_properties)
static Term bv_queue_properties(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE);
  BvRow* physical=bv_child(bv_key(e,f[1]),BV_PHYSICAL,owner);
  if (!owner || !physical) return io_fail(e,BV_INVALID,"invalid physical device or instance");
  BvInstance* instance=owner->context;uint32_t count=0;
  instance->queues((VkPhysicalDevice)(uintptr_t)physical->handle,&count,NULL);
  if (count>4096) return io_fail(e,BV_LIMIT,"too many queue families");
  VkQueueFamilyProperties* values=calloc(count ? count : 1,sizeof(*values));
  if (!values) return io_fail(e,BV_LIMIT,"queue allocation failed");
  instance->queues((VkPhysicalDevice)(uintptr_t)physical->handle,&count,values);
  Term list=term_pak(CID(Nil),0);
  for (uint32_t j=count;j>0;j--) list=io_node(e,CID(Con),io_tup(e,values[j-1].queueFlags,values[j-1].queueCount),list);
  free(values);return io_done(e,list);
}
#endif
#ifdef CID(Instance.memory_types_raw)
static Term bv_memory_types(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE);
  BvRow* physical=bv_child(bv_key(e,f[1]),BV_PHYSICAL,owner);
  if (!owner || !physical) return io_fail(e,BV_INVALID,"invalid physical device or instance");
  BvInstance* instance=owner->context;VkPhysicalDeviceMemoryProperties properties;
  instance->memory((VkPhysicalDevice)(uintptr_t)physical->handle,&properties);
  Term list=term_pak(CID(Nil),0);
  for (uint32_t j=properties.memoryTypeCount;j>0;j--)
    list=io_node(e,CID(Con),io_tup(e,properties.memoryTypes[j-1].propertyFlags,properties.memoryTypes[j-1].heapIndex),list);
  return io_done(e,list);
}
#endif
static char* bv_optional_layer(Env e,Term optional,int* valid) {
  if (term_aux(optional)==CID(None)) return NULL;
  Term fields[1];bv_unpack(e,optional,1,fields);
  uint64_t length=0;char* layer=io_cstr(e,fields[0],&length);
  if (io_nul(layer,length)) *valid=0;
  return layer;
}
typedef enum { BV_LAYERS, BV_INSTANCE_EXTENSIONS, BV_DEVICE_EXTENSIONS } BvEnumerationKind;
typedef struct { BvEnumerationKind kind;BvEntry* entry;BvInstance* instance;VkPhysicalDevice physical; } BvEnumeration;
static VkResult bv_enumerate_call(BvEnumeration query,const char* layer,uint32_t* count,void* data) {
  switch (query.kind) {
    case BV_LAYERS: return query.entry->layers(count,data);
    case BV_INSTANCE_EXTENSIONS: return query.entry->extensions(layer,count,data);
    case BV_DEVICE_EXTENSIONS: return query.instance->extensions(query.physical,layer,count,data);
  }
  return VK_ERROR_INITIALIZATION_FAILED;
}
static uint32_t bv_enumerate(BvEnumeration query,const char* layer,size_t stride,uint32_t* count,void** data,VkResult* status) {
  *data=NULL;*count=0;*status=VK_INCOMPLETE;
  for (unsigned retry=0;retry<8;retry++) {
    free(*data);*data=NULL;
    *status=bv_enumerate_call(query,layer,count,NULL);
    if (*status!=VK_SUCCESS && *status!=VK_INCOMPLETE) return 0;
    if (!*count && *status==VK_SUCCESS) return 0;
    if (*count>4096 || *count>SIZE_MAX/stride) return BV_LIMIT;
    if (!*count) continue;
    *data=calloc(*count,stride);
    if (!*data) return BV_LIMIT;
    *status=bv_enumerate_call(query,layer,count,*data);
    if (*status!=VK_INCOMPLETE) return 0;
  }
  return 0;
}
#ifdef CID(Entry.enumerate_instance_layers)
static Term bv_instance_layers(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_ENTRY);
  if (!owner) return io_fail(e,BV_INVALID,"enumerate_instance_layers: invalid entry");
  BvEnumeration query={.kind=BV_LAYERS,.entry=owner->context};
  uint32_t count=0;void* data=NULL;VkResult status;
  uint32_t code=bv_enumerate(query,NULL,sizeof(VkLayerProperties),&count,&data,&status);
  if (code || status!=VK_SUCCESS) {free(data);return code ? io_fail(e,code,"layer enumeration allocation limit") : bv_vk_error(e,status,"vkEnumerateInstanceLayerProperties");}
  VkLayerProperties* values=data;Term list=term_pak(CID(Nil),0);
  for (uint32_t j=count;j>0;j--) {
    VkLayerProperties* p=&values[j-1];
    Term fields[]={io_str(e,p->layerName,strnlen(p->layerName,VK_MAX_EXTENSION_NAME_SIZE)),p->specVersion,p->implementationVersion,
      io_str(e,p->description,strnlen(p->description,VK_MAX_DESCRIPTION_SIZE))};
    list=io_node(e,CID(Con),bv_node(e,CID(LayerProperties),4,fields),list);
  }
  free(data);return io_done(e,list);
}
#endif
#if defined(CID(Entry.enumerate_instance_extensions)) || defined(CID(Instance.enumerate_device_extensions))
static Term bv_extension_properties(Env e,BvEnumeration query,char* layer,int valid) {
  if (!valid) {free(layer);return io_fail(e,BV_ARGUMENT,"extension layer contains NUL");}
  uint32_t count=0;void* data=NULL;VkResult status;
  uint32_t code=bv_enumerate(query,layer,sizeof(VkExtensionProperties),&count,&data,&status);free(layer);
  if (code || status!=VK_SUCCESS) {free(data);return code ? io_fail(e,code,"extension enumeration allocation limit") :
    bv_vk_error(e,status,query.kind==BV_INSTANCE_EXTENSIONS ? "vkEnumerateInstanceExtensionProperties" : "vkEnumerateDeviceExtensionProperties");}
  VkExtensionProperties* values=data;Term list=term_pak(CID(Nil),0);
  for (uint32_t j=count;j>0;j--) {
    VkExtensionProperties* p=&values[j-1];
    Term fields[]={io_str(e,p->extensionName,strnlen(p->extensionName,VK_MAX_EXTENSION_NAME_SIZE)),p->specVersion};
    list=io_node(e,CID(Con),bv_node(e,CID(ExtensionProperties),2,fields),list);
  }
  free(data);return io_done(e,list);
}
#endif
#ifdef CID(Entry.enumerate_instance_extensions)
static Term bv_instance_extensions(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_ENTRY);int valid=1;char* layer=bv_optional_layer(e,f[1],&valid);
  if (!owner) {free(layer);return io_fail(e,BV_INVALID,"enumerate_instance_extensions: invalid entry");}
  return bv_extension_properties(e,(BvEnumeration){.kind=BV_INSTANCE_EXTENSIONS,.entry=owner->context},layer,valid);
}
#endif
#ifdef CID(Instance.enumerate_device_extensions)
static Term bv_device_extensions(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE);BvRow* physical=bv_child(bv_key(e,f[1]),BV_PHYSICAL,owner);
  int valid=1;char* layer=bv_optional_layer(e,f[2],&valid);
  if (!owner || !physical) {free(layer);return io_fail(e,BV_INVALID,"enumerate_device_extensions: invalid physical device");}
  return bv_extension_properties(e,(BvEnumeration){.kind=BV_DEVICE_EXTENSIONS,.instance=owner->context,
    .physical=(VkPhysicalDevice)(uintptr_t)physical->handle},layer,valid);
}
#endif
#ifdef CID(Instance.memory_heaps_raw)
static Term bv_memory_heaps(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE);BvRow* physical=bv_child(bv_key(e,f[1]),BV_PHYSICAL,owner);
  if (!owner || !physical) return io_fail(e,BV_INVALID,"memory_heaps: invalid physical device");
  BvInstance* instance=owner->context;VkPhysicalDeviceMemoryProperties properties;
  instance->memory((VkPhysicalDevice)(uintptr_t)physical->handle,&properties);
  Term list=term_pak(CID(Nil),0);
  for (uint32_t j=properties.memoryHeapCount;j>0;j--)
    list=io_node(e,CID(Con),io_tup(e,bv_words(e,properties.memoryHeaps[j-1].size),properties.memoryHeaps[j-1].flags),list);
  return io_done(e,list);
}
#endif
#ifdef CID(Instance.get_physical_device_format_properties)
static Term bv_format_properties(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE);BvRow* physical=bv_child(bv_key(e,f[1]),BV_PHYSICAL,owner);
  if (!owner || !physical) return io_fail(e,BV_INVALID,"format_properties: invalid physical device");
  if ((uint32_t)f[2]>VK_FORMAT_ASTC_12x12_SRGB_BLOCK) return io_fail(e,BV_ARGUMENT,"format_properties: expected core Vulkan 1.0 format");
  BvInstance* instance=owner->context;VkFormatProperties properties;
  instance->formats((VkPhysicalDevice)(uintptr_t)physical->handle,(VkFormat)(uint32_t)f[2],&properties);
  Term fields[]={properties.linearTilingFeatures,properties.optimalTilingFeatures,properties.bufferFeatures};
  return io_done(e,bv_node(e,CID(FormatProperties),3,fields));
}
#endif
#ifdef CID(Instance.limits_raw)
static Term bv_physical_limits(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE);BvRow* physical=bv_child(bv_key(e,f[1]),BV_PHYSICAL,owner);
  if (!owner || !physical) return io_fail(e,BV_INVALID,"limits: invalid physical device");
  BvInstance* instance=owner->context;VkPhysicalDeviceProperties properties;
  instance->properties((VkPhysicalDevice)(uintptr_t)physical->handle,&properties);VkPhysicalDeviceLimits* p=&properties.limits;
  uint32_t values[]={p->maxImageDimension2D,p->maxFramebufferWidth,p->maxFramebufferHeight,p->maxColorAttachments,p->maxPushConstantsSize,
    p->maxVertexInputAttributes,p->maxVertexInputBindings,p->maxVertexInputAttributeOffset,p->maxVertexInputBindingStride,p->maxMemoryAllocationCount};
  Term result=io_tup(e,bv_words(e,p->nonCoherentAtomSize),io_tup(e,bv_words(e,p->optimalBufferCopyOffsetAlignment),io_tup(e,bv_words(e,p->optimalBufferCopyRowPitchAlignment),bv_words(e,p->bufferImageGranularity))));
  for (unsigned j=10;j>0;j--) result=io_tup(e,values[j-1],result);
  return io_done(e,result);
}
#endif

#ifdef CID(Instance.create_device)
static Term bv_create_device(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE);
  BvRow* physical=bv_child(bv_key(e,f[1]),BV_PHYSICAL,owner);
  Term info[2];bv_unpack(e,f[2],2,info);BvNames extensions=bv_names(e,info[1]);
  if (!owner || !physical || !extensions.valid) {
    bv_names_free(extensions);return io_fail(e,BV_INVALID,"invalid physical device or extensions");
  }
  BvInstance* instance=owner->context;uint32_t count=0;
  VkPhysicalDevice handle=(VkPhysicalDevice)(uintptr_t)physical->handle;
  instance->queues(handle,&count,NULL);
  if ((uint32_t)info[0]>=count || count>4096) {bv_names_free(extensions);return io_fail(e,BV_ARGUMENT,"queue family out of range");}
  VkQueueFamilyProperties* queues=calloc(count,sizeof(*queues));
  if (!queues) {bv_names_free(extensions);return io_fail(e,BV_LIMIT,"queue allocation failed");}
  instance->queues(handle,&count,queues);
  int valid=queues[(uint32_t)info[0]].queueCount>0;
  VkQueueFamilyProperties queue_properties=queues[(uint32_t)info[0]];
  uint32_t queue_flags=queue_properties.queueFlags;free(queues);
  if (!valid) {bv_names_free(extensions);return io_fail(e,BV_ARGUMENT,"empty queue family");}
  float priority=1.0f;
  VkDeviceQueueCreateInfo queue={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
    .queueFamilyIndex=(uint32_t)info[0],.queueCount=1,.pQueuePriorities=&priority};
  VkDeviceCreateInfo create={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
    .queueCreateInfoCount=1,.pQueueCreateInfos=&queue,.enabledExtensionCount=extensions.count,
    .ppEnabledExtensionNames=(const char* const*)extensions.values};
  VkDevice device;VkResult result=instance->create_device(handle,&create,NULL,&device);
  bv_names_free(extensions);
  if (result!=VK_SUCCESS) return bv_vk_error(e,result,"vkCreateDevice");
  BvDevice* context=calloc(1,sizeof(*context));
  PFN_vkDestroyDevice destroy=(PFN_vkDestroyDevice)instance->get_device(device,"vkDestroyDevice");
  if (!context) {destroy(device,NULL);return io_fail(e,BV_LIMIT,"device allocation failed");}
  context->handle=device;context->physical=handle;context->family=(uint32_t)info[0];context->queue_flags=queue_flags;context->queue_properties=queue_properties;
  VkPhysicalDeviceProperties properties;instance->properties(handle,&properties);context->limits=properties.limits;
  int complete=1;
#define BV_LOAD(name) context->name=(PFN_vk##name)instance->get_device(device,"vk" #name); complete &= context->name!=NULL;
  BV_DEVICE_FUNCTIONS(BV_LOAD)
#undef BV_LOAD
  BvRow* row=complete ? bv_add(BV_DEVICE,owner) : NULL;
  if (!row) {if(destroy)destroy(device,NULL);free(context);return io_fail(e,BV_LIMIT,"device dispatch unavailable");}
  context->GetDeviceQueue(device,context->family,0,&context->queue);
  instance->memory(handle,&context->memory);row->context=context;
  return io_done(e,term_pak(CID(Device),row->id));
}
#endif
#ifdef CID(Device.destroy)
static Term bv_destroy_device_effect(Env e, Term* f, IoWork* w) {
  BvRow* row=bv_get(bv_key(e,f[0]),BV_DEVICE);
  if (!row) return io_fail(e,BV_INVALID,"invalid device");
  BvDevice* device=row->context;
  for (BvRow* child=bv_rows;child;child=child->next)
    if (child->parent==row && child!=device->convenience) return io_fail(e,BV_LIFETIME,"device still has resources");
  VkResult result=bv_idle(row);
  if (result!=VK_SUCCESS && result!=VK_ERROR_DEVICE_LOST) return bv_vk_error(e,result,"vkDeviceWaitIdle");
  bv_destroy_device(row);
  return result==VK_SUCCESS ? bv_ok(e) : bv_vk_error(e,result,"Device.destroy");
}
#endif
#ifdef CID(Device.wait_idle)
static Term bv_device_wait_idle(Env e, Term* f, IoWork* w) {
  BvRow* row=bv_get(bv_key(e,f[0]),BV_DEVICE);
  if (!row) return io_fail(e,BV_INVALID,"invalid device");
  VkResult result=bv_idle(row);
  return result==VK_SUCCESS ? bv_ok(e) : bv_vk_error(e,result,"vkDeviceWaitIdle");
}
#endif
#ifdef CID(Device.create_buffer)
static Term bv_create_buffer(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  // The compiler flattens BufferCreateInfo's single-constructor U64 field.
  Term info[3];bv_unpack(e,f[1],3,info);
  uint64_t size=((uint64_t)(uint32_t)info[1]<<32)|(uint32_t)info[0];
  if (!owner) return io_fail(e,BV_INVALID,"invalid device");
  if (!size || !(uint32_t)info[2]) return io_fail(e,BV_ARGUMENT,"buffer size and usage must be nonzero");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"bv_create_buffer");
  BvDevice* device=owner->context;
  VkBufferCreateInfo create={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
    .size=size,.usage=(uint32_t)info[2],.sharingMode=VK_SHARING_MODE_EXCLUSIVE};
  VkBuffer buffer;VkResult result=device->CreateBuffer(device->handle,&create,NULL,&buffer);
  if (result!=VK_SUCCESS) return bv_device_error(e,owner,result,"vkCreateBuffer");
  BvRow* row=bv_add(BV_BUFFER,owner);
  if (!row) {device->DestroyBuffer(device->handle,buffer,NULL);return io_fail(e,BV_LIMIT,"buffer registry full");}
  row->handle=(uint64_t)(uintptr_t)buffer;row->size=size;row->flags=(uint32_t)info[2];
  device->GetBufferMemoryRequirements(device->handle,buffer,&row->requirements);
  return io_done(e,term_pak(CID(Buffer),row->id));
}
#endif
#ifdef CID(Device.destroy_buffer)
static Term bv_destroy_buffer(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* buffer=bv_child(bv_key(e,f[1]),BV_BUFFER,owner);
  if (!owner || !buffer) return io_fail(e,BV_INVALID,"invalid buffer or device");
  if (bv_referenced(buffer)) return io_fail(e,BV_LIFETIME,"command pool still references buffer");
  BvDevice* device=owner->context;
  device->DestroyBuffer(device->handle,(VkBuffer)(uintptr_t)buffer->handle,NULL);
  bv_remove(buffer);return bv_ok(e);
}
#endif
#ifdef CID(Device.buffer_requirements_raw)
static Term bv_buffer_requirements(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* buffer=bv_child(bv_key(e,f[1]),BV_BUFFER,owner);
  if (!owner || !buffer) return io_fail(e,BV_INVALID,"invalid buffer or device");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"bv_buffer_requirements");
  BvDevice* device=owner->context;VkMemoryRequirements requirements;
  requirements=buffer->requirements;
  return io_done(e,io_tup(e,bv_words(e,requirements.size),
    io_tup(e,bv_words(e,requirements.alignment),requirements.memoryTypeBits)));
}
#endif
#ifdef CID(Device.allocate_memory)
static Term bv_allocate_memory(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);uint64_t size=bv_u64(e,f[1]);
  if (!owner) return io_fail(e,BV_INVALID,"invalid device");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"bv_allocate_memory");
  BvDevice* device=owner->context;uint32_t index=(uint32_t)f[2];
  if (!size || index>=device->memory.memoryTypeCount) return io_fail(e,BV_ARGUMENT,"invalid allocation size or memory type");
  VkMemoryAllocateInfo info={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=size,.memoryTypeIndex=index};
  VkDeviceMemory memory;VkResult result=device->AllocateMemory(device->handle,&info,NULL,&memory);
  if (result!=VK_SUCCESS) return bv_device_error(e,owner,result,"vkAllocateMemory");
  BvRow* row=bv_add(BV_MEMORY,owner);
  if (!row) {device->FreeMemory(device->handle,memory,NULL);return io_fail(e,BV_LIMIT,"memory registry full");}
  row->handle=(uint64_t)(uintptr_t)memory;row->size=size;
  row->flags=device->memory.memoryTypes[index].propertyFlags;row->memory_type=index;
  return io_done(e,term_pak(CID(DeviceMemory),row->id));
}
#endif
#ifdef CID(Device.free_memory)
static Term bv_free_memory(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* memory=bv_child(bv_key(e,f[1]),BV_MEMORY,owner);
  if (!owner || !memory) return io_fail(e,BV_INVALID,"invalid memory or device");
  if (bv_referenced(memory)) return io_fail(e,BV_LIFETIME,"destroy bound resources before freeing memory");
  BvDevice* device=owner->context;
  device->FreeMemory(device->handle,(VkDeviceMemory)(uintptr_t)memory->handle,NULL);
  bv_remove(memory);return bv_ok(e);
}
#endif
static uint32_t bv_binding_check(BvRow* resource,BvRow* memory,uint64_t offset) {
  if (bv_bound_memory(resource)) return BV_LIFETIME;
  VkMemoryRequirements r=resource->requirements;
  if (!r.size || !r.alignment || offset>memory->size || r.size>memory->size-offset || offset%r.alignment ||
      !(r.memoryTypeBits & (1u<<memory->memory_type))) return BV_ARGUMENT;
  uint64_t end=offset+r.size;
  BvDevice* device=resource->parent->context;
  uint64_t g=device->limits.bufferImageGranularity;
  for (BvRow* peer=bv_rows;peer;peer=peer->next) {
    if (peer==resource || bv_bound_memory(peer)!=memory || (peer->kind!=BV_IMAGE && resource->kind!=BV_IMAGE)) continue;
    uint64_t a=bv_bound_offset(peer),b=a+peer->requirements.size;
    if (offset<b && a<end) return BV_ARGUMENT;
    if (peer->kind!=resource->kind && g && (offset/g<=(b-1)/g && a/g<=(end-1)/g)) return BV_ARGUMENT;
  }
  return 0;
}
static Term bv_bind_resource(Env e,Term* f,BvKind kind) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* resource=bv_child(bv_key(e,f[1]),kind,owner);
  BvRow* memory=bv_child(bv_key(e,f[2]),BV_MEMORY,owner);uint64_t offset=bv_u64(e,f[3]);
  if (!owner || !resource || !memory) return io_fail(e,BV_INVALID,"resource and memory must belong to device");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"bind memory");
  uint32_t code=bv_binding_check(resource,memory,offset);
  if (code) return io_fail(e,code,"binding violates lifetime, requirements, overlap or granularity");
  BvDep* binding=malloc(sizeof(*binding));
  if (!binding) return io_fail(e,BV_LIMIT,"binding allocation failed");
  *binding=(BvDep){.target=memory,.role=BV_DEP_BINDING,.offset=offset};
  BvDevice* device=owner->context;
  VkResult result=kind==BV_BUFFER ? device->BindBufferMemory(device->handle,(VkBuffer)(uintptr_t)resource->handle,
    (VkDeviceMemory)(uintptr_t)memory->handle,offset) : device->BindImageMemory(device->handle,(VkImage)(uintptr_t)resource->handle,
    (VkDeviceMemory)(uintptr_t)memory->handle,offset);
  if (result!=VK_SUCCESS) {free(binding);return bv_device_error(e,owner,result,"vkBind resource memory");}
  resource->deps=binding;return bv_ok(e);
}
#ifdef CID(Device.bind_buffer_memory)
static Term bv_bind_buffer_memory(Env e,Term* f,IoWork* w) { return bv_bind_resource(e,f,BV_BUFFER); }
#endif
#ifdef CID(Device.bind_image_memory)
static Term bv_bind_image_memory(Env e,Term* f,IoWork* w) { return bv_bind_resource(e,f,BV_IMAGE); }
#endif

typedef struct { VkFormat format; VkImageAspectFlags aspect; uint32_t bytes; } BvFormat;
static const BvFormat bv_formats[]={
  {VK_FORMAT_R8G8B8A8_UNORM,VK_IMAGE_ASPECT_COLOR_BIT,4},
  {VK_FORMAT_R8G8B8A8_SRGB,VK_IMAGE_ASPECT_COLOR_BIT,4},
  {VK_FORMAT_B8G8R8A8_UNORM,VK_IMAGE_ASPECT_COLOR_BIT,4},
  {VK_FORMAT_B8G8R8A8_SRGB,VK_IMAGE_ASPECT_COLOR_BIT,4},
  {VK_FORMAT_D16_UNORM,VK_IMAGE_ASPECT_DEPTH_BIT,2},
  {VK_FORMAT_D32_SFLOAT,VK_IMAGE_ASPECT_DEPTH_BIT,4}
};
static const BvFormat* bv_format(VkFormat format) {
  for (unsigned j=0;j<sizeof(bv_formats)/sizeof(*bv_formats);j++) if (bv_formats[j].format==format) return &bv_formats[j];
  return NULL;
}
static int bv_image_configuration(uint32_t format,uint32_t type,uint32_t tiling,uint32_t usage,uint32_t flags) {
  if (!format || format>VK_FORMAT_ASTC_12x12_SRGB_BLOCK || type>VK_IMAGE_TYPE_3D || tiling>VK_IMAGE_TILING_LINEAR ||
      !usage || (usage&~255u) || (flags&~31u)) return 0;
  if ((flags&(VK_IMAGE_CREATE_SPARSE_RESIDENCY_BIT|VK_IMAGE_CREATE_SPARSE_ALIASED_BIT)) && !(flags&VK_IMAGE_CREATE_SPARSE_BINDING_BIT)) return 0;
  if ((flags&VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT) && type!=VK_IMAGE_TYPE_2D) return 0;
  if ((usage&VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT) &&
      (!(usage&(VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT|VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT)) ||
       (usage&~(VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT|VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT|VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT)))) return 0;
  return 1;
}
static int bv_image_features(BvInstance* instance,VkPhysicalDevice physical,VkFormat format,VkImageUsageFlags usage) {
  VkFormatProperties p;instance->formats(physical,format,&p);
  VkFormatFeatureFlags required=0;
  if (usage&VK_IMAGE_USAGE_SAMPLED_BIT) required|=VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;
  if (usage&VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT) required|=VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT;
  if (usage&VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) required|=VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT;
  return (p.optimalTilingFeatures&required)==required;
}
static uint32_t bv_mip_dimension(uint32_t base,uint32_t level) {
  return level>=32 || !(base>>level) ? 1 : base>>level;
}
static int bv_range_contains(uint32_t limit,uint32_t base,uint32_t count) {
  return count && base<limit && count<=limit-base;
}
static VkImageSubresourceRange bv_image_range(const Term* p) {
  return (VkImageSubresourceRange){(uint32_t)p[0],(uint32_t)p[1],(uint32_t)p[2],(uint32_t)p[3],(uint32_t)p[4]};
}
static int bv_image_range_valid(BvRow* image,VkImageSubresourceRange r) {
  BvImage* i=&image->object.image;
  return r.aspectMask==bv_format(i->format)->aspect && bv_range_contains(i->mips,r.baseMipLevel,r.levelCount) &&
    bv_range_contains(i->layers,r.baseArrayLayer,r.layerCount);
}
#ifdef CID(Instance.image_format_properties_raw)
static Term bv_image_format_properties(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_INSTANCE),*physical=bv_child(bv_key(e,f[1]),BV_PHYSICAL,owner);
  Term p[5];bv_unpack(e,f[2],5,p);
  if (!owner || !physical) return io_fail(e,BV_INVALID,"image format query ownership");
  if (!bv_image_configuration(p[0],p[1],p[2],p[3],p[4])) return io_fail(e,BV_ARGUMENT,"invalid core image configuration");
  BvInstance* instance=owner->context;VkImageFormatProperties out;
  VkResult result=instance->image_formats((VkPhysicalDevice)(uintptr_t)physical->handle,p[0],p[1],p[2],p[3],p[4],&out);
  if (result!=VK_SUCCESS) return bv_vk_error(e,result,"vkGetPhysicalDeviceImageFormatProperties");
  return io_done(e,io_tup(e,io_tup(e,out.maxExtent.width,out.maxExtent.height),
    io_tup(e,io_tup(e,out.maxExtent.depth,out.maxMipLevels),io_tup(e,io_tup(e,out.maxArrayLayers,out.sampleCounts),bv_words(e,out.maxResourceSize)))));
}
#endif
#ifdef CID(Device.create_image)
static Term bv_create_image(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);Term p[6];bv_unpack(e,f[1],6,p);
  if (!owner) return io_fail(e,BV_INVALID,"invalid device");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"create image");
  const BvFormat* format=bv_format((VkFormat)(uint32_t)p[0]);
  uint32_t usage=p[5],width=p[1],height=p[2],mips=p[3],layers=p[4];
  const uint32_t allowed=VK_IMAGE_USAGE_TRANSFER_SRC_BIT|VK_IMAGE_USAGE_TRANSFER_DST_BIT|VK_IMAGE_USAGE_SAMPLED_BIT|
    VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
  if (!format || !width || !height || !mips || !layers || !usage || (usage&~allowed) ||
      ((usage&VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT) && format->aspect!=VK_IMAGE_ASPECT_COLOR_BIT) ||
      ((usage&VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT) && format->aspect!=VK_IMAGE_ASPECT_DEPTH_BIT))
    return io_fail(e,BV_ARGUMENT,"unsupported image profile");
  uint32_t levels=1;for (uint32_t size=width>height ? width : height;size>1;size>>=1) levels++;
  if (mips>levels) return io_fail(e,BV_ARGUMENT,"mip count exceeds full chain");
  BvDevice* device=owner->context;BvInstance* instance=owner->parent->context;VkImageFormatProperties supported;
  VkResult result=instance->image_formats(device->physical,format->format,VK_IMAGE_TYPE_2D,VK_IMAGE_TILING_OPTIMAL,usage,0,&supported);
  if (result!=VK_SUCCESS) return bv_vk_error(e,result,"vkGetPhysicalDeviceImageFormatProperties");
  if (width>supported.maxExtent.width || height>supported.maxExtent.height || !supported.maxExtent.depth ||
      mips>supported.maxMipLevels || layers>supported.maxArrayLayers || !(supported.sampleCounts&VK_SAMPLE_COUNT_1_BIT) ||
      !bv_image_features(instance,device->physical,format->format,usage)) return io_fail(e,BV_ARGUMENT,"image configuration limits or features");
  VkImageCreateInfo create={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,.format=format->format,
    .extent={width,height,1},.mipLevels=mips,.arrayLayers=layers,.samples=VK_SAMPLE_COUNT_1_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,
    .usage=usage,.sharingMode=VK_SHARING_MODE_EXCLUSIVE,.initialLayout=VK_IMAGE_LAYOUT_UNDEFINED};
  VkImage handle;result=device->CreateImage(device->handle,&create,NULL,&handle);
  if (result!=VK_SUCCESS) return bv_device_error(e,owner,result,"vkCreateImage");
  BvRow* row=bv_add(BV_IMAGE,owner);
  if (!row) {device->DestroyImage(device->handle,handle,NULL);return io_fail(e,BV_LIMIT,"image registry full");}
  row->handle=(uint64_t)(uintptr_t)handle;row->object.image=(BvImage){format->format,{width,height},mips,layers,usage};
  device->GetImageMemoryRequirements(device->handle,handle,&row->requirements);
  return io_done(e,term_pak(CID(ImageHandle),row->id));
}
#endif
#ifdef CID(Device.image_requirements_raw)
static Term bv_image_requirements(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE),*image=bv_child(bv_key(e,f[1]),BV_IMAGE,owner);
  if (!owner || !image) return io_fail(e,BV_INVALID,"image requirements ownership");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"image requirements");
  VkMemoryRequirements r=image->requirements;
  return io_done(e,io_tup(e,bv_words(e,r.size),io_tup(e,bv_words(e,r.alignment),r.memoryTypeBits)));
}
#endif
#ifdef CID(Device.destroy_image)
static Term bv_destroy_image(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE),*image=bv_child(bv_key(e,f[1]),BV_IMAGE,owner);
  if (!owner || !image) return io_fail(e,BV_INVALID,"destroy image ownership");
  if (bv_referenced(image)) return io_fail(e,BV_LIFETIME,"image has incoming dependencies");
  BvDevice* device=owner->context;device->DestroyImage(device->handle,(VkImage)(uintptr_t)image->handle,NULL);
  bv_remove(image);return bv_ok(e);
}
#endif
#ifdef CID(Device.create_image_view)
static Term bv_create_image_view(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);Term p[7];bv_unpack(e,f[1],7,p);
  BvRow* image=bv_child((uint32_t)p[0],BV_IMAGE,owner);
  if (!owner || !image) return io_fail(e,BV_INVALID,"image view ownership");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"create image view");
  if (!bv_bound_memory(image)) return io_fail(e,BV_LIFETIME,"image view requires binding");
  VkImageSubresourceRange range=bv_image_range(p+2);BvImage* i=&image->object.image;
  if (!bv_image_range_valid(image,range) || ((uint32_t)p[1]!=VK_IMAGE_VIEW_TYPE_2D && (uint32_t)p[1]!=VK_IMAGE_VIEW_TYPE_2D_ARRAY) ||
      ((uint32_t)p[1]==VK_IMAGE_VIEW_TYPE_2D && range.layerCount!=1) ||
      !(i->usage&(VK_IMAGE_USAGE_SAMPLED_BIT|VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT)))
    return io_fail(e,BV_ARGUMENT,"image view range, type or usage");
  BvDep* dep=malloc(sizeof(*dep));if (!dep) return io_fail(e,BV_LIMIT,"image view dependency allocation");
  *dep=(BvDep){.target=image,.role=BV_DEP_VIEW_IMAGE};
  VkImageViewCreateInfo create={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=(VkImage)(uintptr_t)image->handle,
    .viewType=(VkImageViewType)(uint32_t)p[1],.format=i->format,.subresourceRange=range};
  BvDevice* device=owner->context;VkImageView handle;VkResult result=device->CreateImageView(device->handle,&create,NULL,&handle);
  if (result!=VK_SUCCESS) {free(dep);return bv_device_error(e,owner,result,"vkCreateImageView");}
  BvRow* row=bv_add(BV_IMAGE_VIEW,owner);
  if (!row) {device->DestroyImageView(device->handle,handle,NULL);free(dep);return io_fail(e,BV_LIMIT,"view registry full");}
  row->handle=(uint64_t)(uintptr_t)handle;row->deps=dep;row->object.view=(BvImageView){create.viewType,range};
  return io_done(e,term_pak(CID(ImageView),row->id));
}
#endif
#ifdef CID(Device.destroy_image_view)
static Term bv_destroy_image_view(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE),*view=bv_child(bv_key(e,f[1]),BV_IMAGE_VIEW,owner);
  if (!owner || !view) return io_fail(e,BV_INVALID,"destroy image view ownership");
  if (bv_referenced(view)) return io_fail(e,BV_LIFETIME,"view has incoming dependencies");
  BvDevice* device=owner->context;device->DestroyImageView(device->handle,(VkImageView)(uintptr_t)view->handle,NULL);
  bv_remove(view);return bv_ok(e);
}
#endif

static int bv_ranges_overlap(VkImageSubresourceRange a,VkImageSubresourceRange b) {
  return (a.aspectMask&b.aspectMask) && a.baseMipLevel<b.baseMipLevel+b.levelCount && b.baseMipLevel<a.baseMipLevel+a.levelCount &&
    a.baseArrayLayer<b.baseArrayLayer+b.layerCount && b.baseArrayLayer<a.baseArrayLayer+a.layerCount;
}
static int bv_image_layout(BvRow* image,uint32_t layout,int old) {
  BvImage* i=&image->object.image;uint32_t aspect=bv_format(i->format)->aspect;
  switch (layout) {
    case VK_IMAGE_LAYOUT_UNDEFINED:return old;
    case VK_IMAGE_LAYOUT_GENERAL:return 1;
    case VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:return aspect==VK_IMAGE_ASPECT_COLOR_BIT && (i->usage&VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT);
    case VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
    case VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL:return aspect==VK_IMAGE_ASPECT_DEPTH_BIT && (i->usage&VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT);
    case VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:return i->usage&VK_IMAGE_USAGE_SAMPLED_BIT;
    case VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL:return i->usage&VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:return i->usage&VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    default:return 0;
  }
}

static int bv_attachment(VkAttachmentDescription* out,uint32_t format,uint32_t load,uint32_t store,int depth) {
  const BvFormat* f=bv_format(format);
  if (!f || f->aspect!=(depth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT) || load>VK_ATTACHMENT_LOAD_OP_DONT_CARE || store>VK_ATTACHMENT_STORE_OP_DONT_CARE) return 0;
  VkImageLayout layout=depth ? VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
  *out=(VkAttachmentDescription){.format=format,.samples=VK_SAMPLE_COUNT_1_BIT,.loadOp=load,.storeOp=store,
    .stencilLoadOp=VK_ATTACHMENT_LOAD_OP_DONT_CARE,.stencilStoreOp=VK_ATTACHMENT_STORE_OP_DONT_CARE,.initialLayout=layout,.finalLayout=layout};
  return 1;
}
#ifdef CID(Device.create_render_pass)
static Term bv_create_render_pass(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);Term info[5];bv_unpack(e,f[1],5,info);
  BvDevice* device=owner ? owner->context : NULL;
  uint32_t code=!owner ? BV_INVALID : !(device->queue_flags&VK_QUEUE_GRAPHICS_BIT) ? BV_ARGUMENT : 0;
  VkAttachmentDescription* attachments=NULL;VkAttachmentReference* colors=NULL;uint32_t count=0;Term list=info[0];
  while (term_aux(list)==CID(Con)) {
    Term item[2],p[3];bv_unpack(e,list,2,item);list=item[1];bv_unpack(e,item[0],3,p);
    if (code) continue;
    VkAttachmentDescription a;
    if (!bv_attachment(&a,p[0],p[1],p[2],0) || !bv_image_features(owner->parent->context,device->physical,p[0],VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)) {code=BV_ARGUMENT;continue;}
    if (count>=device->limits.maxColorAttachments || count>=4095) {code=BV_LIMIT;continue;}
    VkAttachmentDescription* more=realloc(attachments,(count+1)*sizeof(*attachments));
    if (!more) {code=BV_LIMIT;continue;}attachments=more;attachments[count++]=a;
  }
  uint32_t color_count=count;VkAttachmentReference depth={0};
  if (!code && info[1]) {
    VkAttachmentDescription a;
    if (info[1]!=1 || !bv_attachment(&a,info[2],info[3],info[4],1) || !bv_image_features(owner->parent->context,device->physical,info[2],VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT)) code=BV_ARGUMENT;
    else {
      VkAttachmentDescription* more=realloc(attachments,(count+1)*sizeof(*attachments));
      if (!more) code=BV_LIMIT;
      else {attachments=more;depth=(VkAttachmentReference){count,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};attachments[count++]=a;}
    }
  }
  if (!code && !count) code=BV_ARGUMENT;
  if (!code && color_count) {
    colors=malloc(color_count*sizeof(*colors));if (!colors) code=BV_LIMIT;
    else for (uint32_t j=0;j<color_count;j++) colors[j]=(VkAttachmentReference){j,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
  }
  if (owner && bv_lost(owner)) {free(attachments);free(colors);return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"create render pass");}
  if (code) {free(attachments);free(colors);return io_fail(e,code,"render pass attachment schema, queue, limits or allocation");}
  VkSubpassDescription subpass={.pipelineBindPoint=VK_PIPELINE_BIND_POINT_GRAPHICS,.colorAttachmentCount=color_count,
    .pColorAttachments=colors,.pDepthStencilAttachment=info[1] ? &depth : NULL};
  VkRenderPassCreateInfo create={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,.attachmentCount=count,.pAttachments=attachments,
    .subpassCount=1,.pSubpasses=&subpass};
  VkRenderPass handle;VkResult result=device->CreateRenderPass(device->handle,&create,NULL,&handle);free(colors);
  if (result!=VK_SUCCESS) {free(attachments);return bv_device_error(e,owner,result,"vkCreateRenderPass");}
  BvRow* row=bv_add(BV_RENDER_PASS,owner);
  if (!row) {device->DestroyRenderPass(device->handle,handle,NULL);free(attachments);return io_fail(e,BV_LIMIT,"render pass registry full");}
  row->handle=(uint64_t)(uintptr_t)handle;row->object.pass=(BvRenderPass){color_count,count,attachments};
  return io_done(e,term_pak(CID(RenderPass),row->id));
}
#endif
#ifdef CID(Device.destroy_render_pass)
static Term bv_destroy_render_pass(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE),*pass=bv_child(bv_key(e,f[1]),BV_RENDER_PASS,owner);
  if (!owner || !pass) return io_fail(e,BV_INVALID,"destroy render pass ownership");
  if (bv_referenced(pass)) return io_fail(e,BV_LIFETIME,"render pass has incoming dependencies");
  BvDevice* device=owner->context;device->DestroyRenderPass(device->handle,(VkRenderPass)(uintptr_t)pass->handle,NULL);
  bv_remove(pass);return bv_ok(e);
}
#endif
#ifdef CID(Device.create_framebuffer)
static Term bv_create_framebuffer(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);Term info[4];bv_unpack(e,f[1],4,info);
  BvRow* pass=bv_child((uint32_t)info[0],BV_RENDER_PASS,owner);BvDevice* device=owner ? owner->context : NULL;
  uint32_t code=(!owner || !pass) ? BV_INVALID : 0;uint32_t count=pass ? pass->object.pass.count : 0,n=0;
  uint32_t width=info[2],height=info[3];
  if (!code && (!width || !height || width>device->limits.maxFramebufferWidth || height>device->limits.maxFramebufferHeight)) code=BV_ARGUMENT;
  BvDep* staged=NULL;BvDep** attachments=NULL;VkImageView* views=NULL;
  if (!code) {
    attachments=malloc(count*sizeof(*attachments));views=malloc(count*sizeof(*views));
    if (!attachments || !views) code=BV_LIMIT;
  }
  Term list=info[1];
  while (term_aux(list)==CID(Con)) {
    Term item[2];bv_unpack(e,list,2,item);list=item[1];uint32_t id=bv_key(e,item[0]);
    if (code) continue;
    if (n>=count) {code=BV_ARGUMENT;continue;}
    BvRow* view=bv_child(id,BV_IMAGE_VIEW,owner);
    if (!view) {code=BV_INVALID;continue;}
    BvRow* image=bv_dependency(view,BV_DEP_VIEW_IMAGE)->target;BvImageView* v=&view->object.view;BvImage* i=&image->object.image;
    VkAttachmentDescription a=pass->object.pass.attachments[n];int depth=n>=pass->object.pass.colors;
    if (v->type!=VK_IMAGE_VIEW_TYPE_2D || v->range.levelCount!=1 || v->range.layerCount!=1 ||
        i->format!=a.format || v->range.aspectMask!=(depth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT) ||
        !(i->usage&(depth ? VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT : VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT)) ||
        width>bv_mip_dimension(i->extent.width,v->range.baseMipLevel) || height>bv_mip_dimension(i->extent.height,v->range.baseMipLevel)) {code=BV_ARGUMENT;continue;}
    for (uint32_t j=0;j<n;j++) {
      BvRow* previous=attachments[j]->target;
      if (bv_dependency(previous,BV_DEP_VIEW_IMAGE)->target==image && bv_ranges_overlap(previous->object.view.range,v->range)) code=BV_ARGUMENT;
    }
    if (code) continue;
    BvDep* dep=malloc(sizeof(*dep));if (!dep) {code=BV_LIMIT;continue;}
    *dep=(BvDep){.target=view,.role=BV_DEP_FRAMEBUFFER_VIEW,.next=staged};staged=dep;attachments[n]=dep;views[n++]=(VkImageView)(uintptr_t)view->handle;
  }
  if (!code && n!=count) code=BV_ARGUMENT;
  if (!code) {
    BvDep* dep=malloc(sizeof(*dep));if (!dep) code=BV_LIMIT;
    else {*dep=(BvDep){.target=pass,.role=BV_DEP_FRAMEBUFFER_PASS,.next=staged};staged=dep;}
  }
  if (owner && bv_lost(owner)) {free(attachments);free(views);bv_free_refs(staged);return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"create framebuffer");}
  if (code) {free(attachments);free(views);bv_free_refs(staged);return io_fail(e,code,"framebuffer ownership, attachments, extent, overlap or allocation");}
  VkFramebufferCreateInfo create={.sType=VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,.renderPass=(VkRenderPass)(uintptr_t)pass->handle,
    .attachmentCount=count,.pAttachments=views,.width=width,.height=height,.layers=1};
  VkFramebuffer handle;VkResult result=device->CreateFramebuffer(device->handle,&create,NULL,&handle);free(views);
  if (result!=VK_SUCCESS) {free(attachments);bv_free_refs(staged);return bv_device_error(e,owner,result,"vkCreateFramebuffer");}
  BvRow* row=bv_add(BV_FRAMEBUFFER,owner);
  if (!row) {device->DestroyFramebuffer(device->handle,handle,NULL);free(attachments);bv_free_refs(staged);return io_fail(e,BV_LIMIT,"framebuffer registry full");}
  row->handle=(uint64_t)(uintptr_t)handle;row->deps=staged;row->object.framebuffer=(BvFramebuffer){{width,height},count,attachments};
  return io_done(e,term_pak(CID(Framebuffer),row->id));
}
#endif
#ifdef CID(Device.destroy_framebuffer)
static Term bv_destroy_framebuffer(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE),*framebuffer=bv_child(bv_key(e,f[1]),BV_FRAMEBUFFER,owner);
  if (!owner || !framebuffer) return io_fail(e,BV_INVALID,"destroy framebuffer ownership");
  if (bv_referenced(framebuffer)) return io_fail(e,BV_LIFETIME,"framebuffer has incoming dependencies");
  BvDevice* device=owner->context;device->DestroyFramebuffer(device->handle,(VkFramebuffer)(uintptr_t)framebuffer->handle,NULL);
  bv_remove(framebuffer);return bv_ok(e);
}
#endif
#ifdef CID(CommandBuffer.begin_render_pass)
static Term bv_cmd_begin_render_pass(Env e,Term* f,IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND),*owner=bv_command_device(command);
  BvRow* framebuffer=bv_child(bv_key(e,f[1]),BV_FRAMEBUFFER,owner);Term area[4];bv_unpack(e,f[2],4,area);
  BvDevice* device=owner ? owner->context : NULL;
  uint32_t code=(!command || !framebuffer) ? BV_INVALID : !bv_outside(command) ? BV_LIFETIME : !(device->queue_flags&VK_QUEUE_GRAPHICS_BIT) ? BV_ARGUMENT : 0;
  BvRow* pass=framebuffer ? bv_dependency(framebuffer,BV_DEP_FRAMEBUFFER_PASS)->target : NULL;
  uint32_t count=pass ? pass->object.pass.count : 0,n=0;VkClearValue* clears=NULL;
  if (!code) {
    VkExtent2D extent=framebuffer->object.framebuffer.extent;uint32_t x=area[0],y=area[1],w=area[2],h=area[3];
    if (x>INT32_MAX || y>INT32_MAX || !w || !h || w>INT32_MAX || h>INT32_MAX || x>extent.width || w>extent.width-x || y>extent.height || h>extent.height-y) code=BV_ARGUMENT;
    else {clears=calloc(count,sizeof(*clears));if (!clears) code=BV_LIMIT;}
  }
  Term list=f[3];
  while (term_aux(list)==CID(Con)) {
    Term item[2];bv_unpack(e,list,2,item);list=item[1];
    if (code) {term_sink(e,item[0]);continue;}
    if (n>=count) {term_sink(e,item[0]);code=BV_ARGUMENT;continue;}
    VkAttachmentDescription a=pass->object.pass.attachments[n];uint64_t tag=term_aux(item[0]);
    if (a.loadOp!=VK_ATTACHMENT_LOAD_OP_CLEAR) {if (tag!=CID(UnusedClear)) code=BV_ARGUMENT;term_sink(e,item[0]);}
    else if (n<pass->object.pass.colors && tag==CID(ColorClear)) {
      Term lanes[4];bv_unpack(e,item[0],4,lanes);
      for (unsigned j=0;j<4;j++) {clears[n].color.float32[j]=f32_unbox(lanes[j]);if (!isfinite(clears[n].color.float32[j])) code=BV_ARGUMENT;}
    } else if (n>=pass->object.pass.colors && tag==CID(DepthClear)) {
      float depth=f32_unbox(bv_key(e,item[0]));if (!isfinite(depth) || depth<0 || depth>1) code=BV_ARGUMENT;
      clears[n].depthStencil=(VkClearDepthStencilValue){depth,0};
    } else {term_sink(e,item[0]);code=BV_ARGUMENT;}
    n++;
  }
  if (!code && n!=count) code=BV_ARGUMENT;
  if (owner && bv_lost(owner)) {free(clears);return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"begin render pass");}
  if (!code && !bv_prepare_refs(command,1,&framebuffer)) code=BV_LIMIT;
  if (!code) {
    VkRenderPassBeginInfo begin={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,.renderPass=(VkRenderPass)(uintptr_t)pass->handle,
      .framebuffer=(VkFramebuffer)(uintptr_t)framebuffer->handle,.renderArea={{area[0],area[1]},{area[2],area[3]}},.clearValueCount=count,.pClearValues=clears};
    device->CmdBeginRenderPass((VkCommandBuffer)(uintptr_t)command->handle,&begin,VK_SUBPASS_CONTENTS_INLINE);
    command->command.submission.recording.scope=(BvRenderScope){.tag=BV_INSIDE,.data.inside={framebuffer}};
  }
  free(clears);return code ? io_fail(e,code,"begin render pass ownership, scope, area, typed clears or allocation") : bv_ok(e);
}
#endif
#ifdef CID(CommandBuffer.end_render_pass)
static Term bv_cmd_end_render_pass(Env e,Term* f,IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);
  if (!command) return io_fail(e,BV_INVALID,"invalid command buffer");
  BvRow* owner=bv_command_device(command);BvDevice* device=owner->context;
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"end render pass");
  if (command->command.phase!=BV_RECORDING || command->command.submission.recording.scope.tag!=BV_INSIDE) return io_fail(e,BV_LIFETIME,"end render pass requires Inside recording scope");
  device->CmdEndRenderPass((VkCommandBuffer)(uintptr_t)command->handle);
  command->command.submission.recording.scope=(BvRenderScope){.tag=BV_OUTSIDE};return bv_ok(e);
}
#endif

// Map whole allocations so cache ranges satisfy nonCoherentAtomSize alignment.
static int bv_map_range(BvRow* memory,uint64_t offset,uint32_t count) {
  return (memory->flags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) && offset<=memory->size &&
      count<=memory->size-offset && offset<=SIZE_MAX && count<=SIZE_MAX-(size_t)offset;
}
static VkResult bv_map(BvRow* owner,BvRow* memory,void** mapped) {
  BvDevice* device=owner->context;
  return device->MapMemory(device->handle,(VkDeviceMemory)(uintptr_t)memory->handle,0,VK_WHOLE_SIZE,0,mapped);
}
#ifdef CID(Device.write_memory)
static Term bv_write_memory(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* memory=bv_child(bv_key(e,f[1]),BV_MEMORY,owner);uint64_t offset=bv_u64(e,f[2]);
  uint32_t count=0,capacity=64;int valid=1;uint8_t* bytes=malloc(capacity);Term list=f[3];
  if (!bytes) {term_sink(e,list);return io_fail(e,BV_LIMIT,"copy allocation failed");}
  while (term_aux(list)==CID(Con)) {
    Term fields[2];bv_unpack(e,list,2,fields);list=fields[1];
    if ((uint32_t)fields[0]>255 || count>=BV_MAX_COPY) valid=0;
    if (count>=BV_MAX_COPY) {term_sink(e,list);break;}
    if (count==capacity) {
      capacity*=2;uint8_t* grown=realloc(bytes,capacity);
      if (!grown) {term_sink(e,list);free(bytes);return io_fail(e,BV_LIMIT,"copy allocation failed");}bytes=grown;
    }
    bytes[count++]=(uint8_t)fields[0];
  }
  if (!owner || !memory || !valid) {free(bytes);return io_fail(e,valid ? BV_INVALID : BV_ARGUMENT,"invalid memory, byte value, or copy length");}
  if (bv_lost(owner)) {free(bytes);return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"write_memory");}
  if (bv_memory_busy(memory)) {free(bytes);return io_fail(e,BV_LIFETIME,"write_memory: allocation is in use");}
  if (!bv_map_range(memory,offset,count)) {free(bytes);return io_fail(e,BV_ARGUMENT,"write needs host-visible memory and an in-bounds range");}
  if (!count) {free(bytes);return offset<=memory->size ? bv_ok(e) : io_fail(e,BV_ARGUMENT,"copy offset out of range");}
  void* mapped=NULL;VkResult result=bv_map(owner,memory,&mapped);BvDevice* device=owner->context;
  if (result==VK_SUCCESS) {
    memcpy((uint8_t*)mapped+(size_t)offset,bytes,count);
    if (!(memory->flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
      VkMappedMemoryRange range={.sType=VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        .memory=(VkDeviceMemory)(uintptr_t)memory->handle,.offset=0,.size=VK_WHOLE_SIZE};
      result=device->FlushMappedMemoryRanges(device->handle,1,&range);
    }
    device->UnmapMemory(device->handle,(VkDeviceMemory)(uintptr_t)memory->handle);
  }
  free(bytes);return result==VK_SUCCESS ? bv_ok(e) : bv_device_error(e,owner,result,"write_memory / map or flush");
}
#endif
#ifdef CID(Device.write_memory_words)
static Term bv_write_memory_words(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* memory=bv_child(bv_key(e,f[1]),BV_MEMORY,owner);
  uint64_t offset=bv_u64(e,f[2]), count=bv_u64(e,f[3]); Term words=f[4], result;
  if (!owner || !memory) result=io_fail(e,BV_INVALID,"write_memory_words: invalid device or memory");
  else if (bv_lost(owner)) result=bv_vk_error(e,VK_ERROR_DEVICE_LOST,"write_memory_words");
  else if (bv_memory_busy(memory)) result=io_fail(e,BV_LIFETIME,"write_memory_words: allocation is in use");
  else if (term_tag(words)!=TAG_BUF && term_tag(words)!=TAG_ARR)
    result=io_fail(e,BV_ARGUMENT,"write_memory_words: expected U32 array");
  else if (count>BV_MAX_COPY || count>SIZE_MAX) result=io_fail(e,BV_LIMIT,"write_memory_words: 16 MiB chunk limit");
  else if (count>(UINT64_C(1)<<blk_cls(words))*4 || !bv_map_range(memory,offset,(uint32_t)count))
    result=io_fail(e,BV_ARGUMENT,"write_memory_words: array capacity or mapped range");
  else if (!count) result=bv_ok(e);
  else {
    void* mapped=NULL; BvDevice* device=owner->context; VkResult status=bv_map(owner,memory,&mapped);
    if (status==VK_SUCCESS) {
      uint64_t location=blk_loc(e.mem,words); bool terms=term_tag(words)==TAG_ARR;
      for (uint32_t j=0;j<(uint32_t)count;j++) {
        uint32_t value=(uint32_t)blk_read(e.mem,terms,location,j/4);
        ((uint8_t*)mapped)[(size_t)offset+j]=(uint8_t)(value>>(8*(j%4)));
      }
      if (!(memory->flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
        VkMappedMemoryRange range={.sType=VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
          .memory=(VkDeviceMemory)(uintptr_t)memory->handle,.offset=0,.size=VK_WHOLE_SIZE};
        status=device->FlushMappedMemoryRanges(device->handle,1,&range);
      }
      device->UnmapMemory(device->handle,(VkDeviceMemory)(uintptr_t)memory->handle);
    }
    result=status==VK_SUCCESS ? bv_ok(e) : bv_device_error(e,owner,status,"write_memory_words / map or flush");
  }
  return io_tup(e,words,result);
}
#endif
#ifdef CID(Device.read_memory)
static Term bv_read_memory(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* memory=bv_child(bv_key(e,f[1]),BV_MEMORY,owner);uint64_t offset=bv_u64(e,f[2]);uint32_t count=(uint32_t)f[3];
  if (!owner || !memory) return io_fail(e,BV_INVALID,"invalid memory or device");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"read_memory");
  if (bv_memory_busy(memory)) return io_fail(e,BV_LIFETIME,"read_memory: allocation is in use");
  if (count>BV_MAX_COPY) return io_fail(e,BV_LIMIT,"read exceeds 16 MiB chunk limit");
  if (!bv_map_range(memory,offset,count)) return io_fail(e,BV_ARGUMENT,"read needs host-visible memory and an in-bounds range");
  if (!count) return offset<=memory->size ? io_done(e,term_pak(CID(Nil),0)) : io_fail(e,BV_ARGUMENT,"copy offset out of range");
  void* mapped=NULL;VkResult result=bv_map(owner,memory,&mapped);BvDevice* device=owner->context;
  Term list=term_pak(CID(Nil),0);
  if (result==VK_SUCCESS) {
    if (!(memory->flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
      VkMappedMemoryRange range={.sType=VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,
        .memory=(VkDeviceMemory)(uintptr_t)memory->handle,.offset=0,.size=VK_WHOLE_SIZE};
      result=device->InvalidateMappedMemoryRanges(device->handle,1,&range);
    }
    if (result==VK_SUCCESS)
      for (uint32_t j=count;j>0;j--) list=io_node(e,CID(Con),((uint8_t*)mapped)[(size_t)offset+j-1],list);
    device->UnmapMemory(device->handle,(VkDeviceMemory)(uintptr_t)memory->handle);
  }
  return result==VK_SUCCESS ? io_done(e,list) : bv_device_error(e,owner,result,"read_memory / map or invalidate");
}
#endif
#ifdef CID(Device.create_command_pool)
static Term bv_create_command_pool(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  if (!owner) return io_fail(e,BV_INVALID,"invalid device");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"bv_create_command_pool");
  BvDevice* device=owner->context;
  if (!(device->queue_flags & (VK_QUEUE_GRAPHICS_BIT|VK_QUEUE_COMPUTE_BIT|VK_QUEUE_TRANSFER_BIT)))
    return io_fail(e,BV_ARGUMENT,"command pool needs a transfer-capable queue family");
  VkCommandPoolCreateInfo info={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.queueFamilyIndex=device->family,.flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT};
  VkCommandPool pool;VkResult result=device->CreateCommandPool(device->handle,&info,NULL,&pool);
  if (result!=VK_SUCCESS) return bv_device_error(e,owner,result,"vkCreateCommandPool");
  BvRow* row=bv_add(BV_POOL,owner);
  if (!row) {device->DestroyCommandPool(device->handle,pool,NULL);return io_fail(e,BV_LIMIT,"command pool registry full");}
  row->handle=(uint64_t)(uintptr_t)pool;
  return io_done(e,term_pak(CID(CommandPool),row->id));
}
#endif
#ifdef CID(Device.destroy_command_pool)
static Term bv_destroy_command_pool(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);BvRow* pool=bv_child(bv_key(e,f[1]),BV_POOL,owner);
  if (!owner || !pool) return io_fail(e,BV_INVALID,"invalid command pool or device");
  for (BvRow* row=bv_rows;row;row=row->next)
    if (row->parent==pool && bv_command_fence(row)) return io_fail(e,BV_LIFETIME,"pool has active commands");
  bv_destroy_pool(pool);return bv_ok(e);
}
#endif
#ifdef CID(Device.allocate_command_buffer)
static Term bv_allocate_command_buffer(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);BvRow* pool=bv_child(bv_key(e,f[1]),BV_POOL,owner);
  if (!owner || !pool) return io_fail(e,BV_INVALID,"invalid command pool or device");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"bv_allocate_command_buffer");
  BvDevice* device=owner->context;BvRow* row=bv_add(BV_COMMAND,pool);
  if (!row) return io_fail(e,BV_LIMIT,"command buffer registry full");
  VkCommandBufferAllocateInfo info={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    .commandPool=(VkCommandPool)(uintptr_t)pool->handle,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
  VkCommandBuffer command;VkResult result=device->AllocateCommandBuffers(device->handle,&info,&command);
  if (result!=VK_SUCCESS) {bv_remove(row);return bv_device_error(e,owner,result,"vkAllocateCommandBuffers");}
  row->handle=(uint64_t)(uintptr_t)command;
  return io_done(e,term_pak(CID(CommandBuffer),row->id));
}
#endif
#ifdef CID(CommandBuffer.begin)
static Term bv_begin_command_buffer(Env e, Term* f, IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);
  if (!command) return io_fail(e,BV_INVALID,"invalid command buffer");
  if (bv_lost(bv_command_device(command))) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"bv_begin_command_buffer");
  if (command->command.phase!=BV_INITIAL) return io_fail(e,BV_LIFETIME,"begin requires Initial; reset before re-recording");
  BvDevice* device=bv_command_device(command)->context;
  VkCommandBufferBeginInfo info={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
  VkResult result=device->BeginCommandBuffer((VkCommandBuffer)(uintptr_t)command->handle,&info);
  if (result!=VK_SUCCESS) {command->command.phase=BV_COMMAND_INVALID;return bv_device_error(e,bv_command_device(command),result,"vkBeginCommandBuffer");}
  command->command.phase=BV_RECORDING;command->command.submission.recording.scope=(BvRenderScope){.tag=BV_OUTSIDE};return bv_ok(e);
}
#endif
#ifdef CID(CommandBuffer.fill_buffer)
static Term bv_cmd_fill_buffer(Env e, Term* f, IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);uint32_t id=bv_key(e,f[1]);
  uint64_t offset=bv_u64(e,f[2]),size=bv_u64(e,f[3]);
  BvRow* owner=bv_command_device(command);BvRow* buffer=bv_child(id,BV_BUFFER,owner);
  if (!command || !buffer) return io_fail(e,BV_INVALID,"command and buffer must belong to same device");
  if (bv_lost(bv_command_device(command))) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"bv_cmd_fill_buffer");
  if (!bv_outside(command) || !bv_bound_memory(buffer)) return io_fail(e,BV_LIFETIME,"fill needs recording command and bound buffer");
  if (size==VK_WHOLE_SIZE && offset<buffer->size) size=(buffer->size-offset)&~UINT64_C(3);
  if (!size || offset>buffer->size || size>buffer->size-offset || ((offset|size)&3) || !(buffer->flags & VK_BUFFER_USAGE_TRANSFER_DST_BIT))
    return io_fail(e,BV_ARGUMENT,"invalid fill offset, size, alignment, or usage");
  if (!bv_prepare_refs(command,1,&buffer)) return io_fail(e,BV_LIMIT,"command reference allocation failed");
  BvDevice* device=owner->context;
  device->CmdFillBuffer((VkCommandBuffer)(uintptr_t)command->handle,(VkBuffer)(uintptr_t)buffer->handle,offset,size,(uint32_t)f[4]);
  return bv_ok(e);
}
#endif
static int bv_overlap(uint64_t a, uint64_t na, uint64_t b, uint64_t nb) {
  return a<=b ? b-a<na : a-b<nb;
}
#ifdef CID(CommandBuffer.copy_buffer)
static Term bv_cmd_copy_buffer(Env e, Term* f, IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND); BvRow* owner=bv_command_device(command);
  BvRow* src=bv_child(bv_key(e,f[1]),BV_BUFFER,owner);
  BvRow* dst=bv_child(bv_key(e,f[2]),BV_BUFFER,owner);
  uint32_t code=(!command || !src || !dst) ? BV_INVALID :
    (!bv_outside(command) || !bv_bound_memory(src) || !bv_bound_memory(dst)) ? BV_LIFETIME :
    (!(src->flags & VK_BUFFER_USAGE_TRANSFER_SRC_BIT) || !(dst->flags & VK_BUFFER_USAGE_TRANSFER_DST_BIT)) ? BV_ARGUMENT : 0;
  VkBufferCopy* regions=NULL; uint32_t count=0; Term list=f[3];
  while (term_aux(list)==CID(Con)) {
    Term item[2],fields[6]; bv_unpack(e,list,2,item);list=item[1];bv_unpack(e,item[0],6,fields);
    if (code) continue;
    uint64_t a=((uint64_t)(uint32_t)fields[1]<<32)|(uint32_t)fields[0];
    uint64_t b=((uint64_t)(uint32_t)fields[3]<<32)|(uint32_t)fields[2];
    uint64_t n=((uint64_t)(uint32_t)fields[5]<<32)|(uint32_t)fields[4];
    if (!n || a>src->size || n>src->size-a || b>dst->size || n>dst->size-b) {code=BV_ARGUMENT;continue;}
    if (count>=4096) {code=BV_LIMIT;continue;}
    VkBufferCopy* more=realloc(regions,(count+1)*sizeof(*regions));
    if (!more) {code=BV_LIMIT;continue;} regions=more;
    regions[count++]=(VkBufferCopy){.srcOffset=a,.dstOffset=b,.size=n};
  }
  if (!code && !count) code=BV_ARGUMENT;
  for (uint32_t j=0;!code && j<count;j++) {
    for (uint32_t k=0;k<count;k++) {
      if ((j!=k && bv_overlap(regions[j].dstOffset,regions[j].size,regions[k].dstOffset,regions[k].size)) ||
          (bv_bound_memory(src)==bv_bound_memory(dst) && bv_overlap(bv_bound_offset(src)+regions[j].srcOffset,regions[j].size,
            bv_bound_offset(dst)+regions[k].dstOffset,regions[k].size))) {code=BV_ARGUMENT;break;}
    }
  }
  BvRow* resources[]={src,dst};
  if (owner && bv_lost(owner)) {free(regions);return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"copy_buffer");}
  if (!code && !bv_prepare_refs(command,2,resources)) code=BV_LIMIT;
  if (!code) {
    BvDevice* device=owner->context;
    device->CmdCopyBuffer((VkCommandBuffer)(uintptr_t)command->handle,(VkBuffer)(uintptr_t)src->handle,
      (VkBuffer)(uintptr_t)dst->handle,count,regions);
  }
  free(regions);
  return code ? io_fail(e,code,"copy_buffer: invalid state, usage, range, alias overlap, or allocation") : bv_ok(e);
}
#endif
#ifdef CID(CommandBuffer.pipeline_barrier)
static Term bv_cmd_pipeline_barrier(Env e, Term* f, IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);
  BvRow* owner=bv_command_device(command);
  BvDevice* device=owner ? owner->context : NULL;
  uint32_t src=device ? bv_baseline_stages(device,(uint32_t)f[1]) : 0;
  uint32_t dst=device ? bv_baseline_stages(device,(uint32_t)f[2]) : 0;
  uint32_t code=!command ? BV_INVALID : !bv_outside(command) ? BV_LIFETIME : (!src || !dst) ? BV_ARGUMENT : 0;
  VkMemoryBarrier* memory=NULL; VkBufferMemoryBarrier* buffers=NULL; VkImageMemoryBarrier* images=NULL; BvRow** resources=NULL;
  uint32_t nm=0,nb=0,ni=0; Term list=f[3];
  while (term_aux(list)==CID(Con)) {
    Term item[2],fields[2]; bv_unpack(e,list,2,item); list=item[1]; bv_unpack(e,item[0],2,fields);
    if (code) continue;
    if (nm>=4096) {code=BV_LIMIT;continue;}
    if (!bv_access(src,(uint32_t)fields[0]) || !bv_access(dst,(uint32_t)fields[1])) {code=BV_ARGUMENT;continue;}
    VkMemoryBarrier* more=realloc(memory,(nm+1)*sizeof(*memory));
    if (!more) {code=BV_LIMIT;continue;} memory=more;
    memory[nm++]=(VkMemoryBarrier){.sType=VK_STRUCTURE_TYPE_MEMORY_BARRIER,.srcAccessMask=(uint32_t)fields[0],.dstAccessMask=(uint32_t)fields[1]};
  }
  list=f[4];
  while (term_aux(list)==CID(Con)) {
    Term item[2],fields[7]; bv_unpack(e,list,2,item);list=item[1];bv_unpack(e,item[0],7,fields);
    if (code) continue;
    BvRow* buffer=bv_child((uint32_t)fields[0],BV_BUFFER,owner);
    uint64_t offset=((uint64_t)(uint32_t)fields[2]<<32)|(uint32_t)fields[1];
    uint64_t size=((uint64_t)(uint32_t)fields[4]<<32)|(uint32_t)fields[3];
    if (!buffer) {code=BV_INVALID;continue;}
    if (!bv_bound_memory(buffer)) {code=BV_LIFETIME;continue;}
    if (size==VK_WHOLE_SIZE && offset<buffer->size) size=buffer->size-offset;
    if (!size || offset>buffer->size || size>buffer->size-offset ||
        !bv_access(src,(uint32_t)fields[5]) || !bv_access(dst,(uint32_t)fields[6])) {code=BV_ARGUMENT;continue;}
    if (nb>=4096) {code=BV_LIMIT;continue;}
    VkBufferMemoryBarrier* more=realloc(buffers,(nb+1)*sizeof(*buffers));
    if (!more) {code=BV_LIMIT;continue;} buffers=more;
    BvRow** refs=realloc(resources,(nb+1)*sizeof(*resources));
    if (!refs) {code=BV_LIMIT;continue;} resources=refs;
    resources[nb]=buffer;
    buffers[nb++]=(VkBufferMemoryBarrier){.sType=VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER,
      .srcAccessMask=(uint32_t)fields[5],.dstAccessMask=(uint32_t)fields[6],
      .srcQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,.dstQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,
      .buffer=(VkBuffer)(uintptr_t)buffer->handle,.offset=offset,.size=size};
  }
  list=f[5];
  while (term_aux(list)==CID(Con)) {
    Term item[2],p[10];bv_unpack(e,list,2,item);list=item[1];bv_unpack(e,item[0],10,p);
    if (code) continue;
    BvRow* image=bv_child((uint32_t)p[0],BV_IMAGE,owner);
    if (!image) {code=BV_INVALID;continue;}
    if (!bv_bound_memory(image)) {code=BV_LIFETIME;continue;}
    VkImageSubresourceRange range=bv_image_range(p+1);
    if (!bv_image_range_valid(image,range) || !bv_image_layout(image,p[6],1) || !bv_image_layout(image,p[7],0) ||
        (!p[6] && p[8]) || !bv_access(src,p[8]) || !bv_access(dst,p[9])) {code=BV_ARGUMENT;continue;}
    for (uint32_t j=0;j<ni;j++) if (images[j].image==(VkImage)(uintptr_t)image->handle && bv_ranges_overlap(images[j].subresourceRange,range)) code=BV_ARGUMENT;
    if (code) continue;
    if (ni>=4096) {code=BV_LIMIT;continue;}
    VkImageMemoryBarrier* more=realloc(images,(ni+1)*sizeof(*images));
    if (!more) {code=BV_LIMIT;continue;}images=more;
    BvRow** refs=realloc(resources,(nb+ni+1)*sizeof(*resources));
    if (!refs) {code=BV_LIMIT;continue;}resources=refs;resources[nb+ni]=image;
    images[ni++]=(VkImageMemoryBarrier){.sType=VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
      .srcAccessMask=p[8],.dstAccessMask=p[9],.oldLayout=p[6],.newLayout=p[7],
      .srcQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,.dstQueueFamilyIndex=VK_QUEUE_FAMILY_IGNORED,
      .image=(VkImage)(uintptr_t)image->handle,.subresourceRange=range};
  }
  if (owner && bv_lost(owner)) {free(memory);free(buffers);free(images);free(resources);return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"pipeline_barrier");}
  if (!code && !bv_prepare_refs(command,nb+ni,resources)) code=BV_LIMIT;
  if (!code) device->CmdPipelineBarrier((VkCommandBuffer)(uintptr_t)command->handle,
    (uint32_t)f[1],(uint32_t)f[2],0,nm,memory,nb,buffers,ni,images);
  free(memory);free(buffers);free(images);free(resources);
  return code ? io_fail(e,code,"pipeline_barrier: invalid state, stages, access, layout, range, or allocation") : bv_ok(e);
}
#endif
static int bv_add64(uint64_t a,uint64_t b,uint64_t* out) {
  if (b>UINT64_MAX-a) return 0;
  *out=a+b;return 1;
}
static int bv_mul64(uint64_t a,uint64_t b,uint64_t* out) {
  if (b && a>UINT64_MAX/b) return 0;
  *out=a*b;return 1;
}
static int bv_copy_end(uint64_t offset,uint32_t row_length,uint32_t image_height,uint32_t width,uint32_t height,uint32_t layers,uint32_t bytes,uint64_t* end) {
  uint64_t row,layer,last_layer,last_row,payload,total;
  uint32_t r=row_length ? row_length : width,h=image_height ? image_height : height;
  return width && height && layers && bytes && r>=width && h>=height &&
    bv_mul64(r,bytes,&row) && bv_mul64(h,row,&layer) && bv_mul64(layers-1,layer,&last_layer) &&
    bv_mul64(height-1,row,&last_row) && bv_mul64(width,bytes,&payload) &&
    bv_add64(last_layer,last_row,&total) && bv_add64(total,payload,&total) && bv_add64(offset,total,end);
}
static int bv_transfer_axis(uint32_t offset,uint32_t extent,uint32_t limit,uint32_t granularity) {
  return !granularity ? (!offset && extent==limit) : !(offset%granularity) && (!(extent%granularity) || extent==limit-offset);
}
static uint32_t bv_image_command_state(BvRow* command,BvRow* image,uint32_t usage,uint32_t layout) {
  if (!command || !image) return BV_INVALID;
  if (!bv_outside(command) || !bv_bound_memory(image)) return BV_LIFETIME;
  if (!(image->object.image.usage&usage) || (layout!=VK_IMAGE_LAYOUT_GENERAL &&
      layout!=(usage==VK_IMAGE_USAGE_TRANSFER_SRC_BIT ? VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL : VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL))) return BV_ARGUMENT;
  return 0;
}
#if defined(CID(CommandBuffer.clear_color_image)) || defined(CID(CommandBuffer.clear_depth_image))
static Term bv_clear_image(Env e,Term* f,int depth) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND),*owner=bv_command_device(command);
  BvRow* image=bv_child(bv_key(e,f[1]),BV_IMAGE,owner);uint32_t layout=f[2];
  uint32_t code=bv_image_command_state(command,image,VK_IMAGE_USAGE_TRANSFER_DST_BIT,layout);
  VkClearColorValue color={0};VkClearDepthStencilValue value={0};
  if (depth) {value.depth=f32_unbox(f[3]);if (!isfinite(value.depth) || value.depth<0 || value.depth>1) code=BV_ARGUMENT;}
  else {
    Term lanes[4];bv_unpack(e,f[3],4,lanes);
    for (unsigned j=0;j<4;j++) {color.float32[j]=f32_unbox(lanes[j]);if (!isfinite(color.float32[j])) code=BV_ARGUMENT;}
  }
  BvDevice* device=owner ? owner->context : NULL;
  if (!code && (bv_format(image->object.image.format)->aspect!=(depth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT) ||
      !(device->queue_flags&(depth ? VK_QUEUE_GRAPHICS_BIT : VK_QUEUE_GRAPHICS_BIT|VK_QUEUE_COMPUTE_BIT)))) code=BV_ARGUMENT;
  VkImageSubresourceRange* ranges=NULL;uint32_t count=0;Term list=f[4];
  while (term_aux(list)==CID(Con)) {
    Term item[2],p[5];bv_unpack(e,list,2,item);list=item[1];bv_unpack(e,item[0],5,p);
    if (code) continue;
    VkImageSubresourceRange range=bv_image_range(p);
    if (!bv_image_range_valid(image,range)) {code=BV_ARGUMENT;continue;}
    for (uint32_t j=0;j<count;j++) if (bv_ranges_overlap(range,ranges[j])) code=BV_ARGUMENT;
    if (code) continue;
    if (count>=4096) {code=BV_LIMIT;continue;}
    VkImageSubresourceRange* more=realloc(ranges,(count+1)*sizeof(*ranges));
    if (!more) {code=BV_LIMIT;continue;}ranges=more;ranges[count++]=range;
  }
  if (!code && !count) code=BV_ARGUMENT;
  if (owner && bv_lost(owner)) {free(ranges);return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"clear image");}
  if (!code && !bv_prepare_refs(command,1,&image)) code=BV_LIMIT;
  if (!code) {
    if (depth) device->CmdClearDepthStencilImage((VkCommandBuffer)(uintptr_t)command->handle,(VkImage)(uintptr_t)image->handle,layout,&value,count,ranges);
    else device->CmdClearColorImage((VkCommandBuffer)(uintptr_t)command->handle,(VkImage)(uintptr_t)image->handle,layout,&color,count,ranges);
  }
  free(ranges);return code ? io_fail(e,code,"clear image state, queue, layout, values, ranges or allocation") : bv_ok(e);
}
#endif
#ifdef CID(CommandBuffer.clear_color_image)
static Term bv_cmd_clear_color_image(Env e,Term* f,IoWork* w) {return bv_clear_image(e,f,0);}
#endif
#ifdef CID(CommandBuffer.clear_depth_image)
static Term bv_cmd_clear_depth_image(Env e,Term* f,IoWork* w) {return bv_clear_image(e,f,1);}
#endif
#if defined(CID(CommandBuffer.copy_buffer_to_image)) || defined(CID(CommandBuffer.copy_image_to_buffer))
static Term bv_copy_image_buffer(Env e,Term* f,int upload) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND),*owner=bv_command_device(command);
  BvRow* image=bv_child(bv_key(e,f[upload ? 2 : 1]),BV_IMAGE,owner);
  BvRow* buffer=bv_child(bv_key(e,f[upload ? 1 : 3]),BV_BUFFER,owner);
  uint32_t layout=f[upload ? 3 : 2],usage=upload ? VK_IMAGE_USAGE_TRANSFER_DST_BIT : VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
  uint32_t code=bv_image_command_state(command,image,usage,layout);
  BvDevice* device=owner ? owner->context : NULL;const BvFormat* format=image ? bv_format(image->object.image.format) : NULL;
  if (!buffer) code=BV_INVALID;
  else if (!bv_bound_memory(buffer)) code=BV_LIFETIME;
  else if (!(buffer->flags&(upload ? VK_BUFFER_USAGE_TRANSFER_SRC_BIT : VK_BUFFER_USAGE_TRANSFER_DST_BIT))) code=BV_ARGUMENT;
  if (!code && (!(device->queue_flags&(VK_QUEUE_GRAPHICS_BIT|VK_QUEUE_COMPUTE_BIT|VK_QUEUE_TRANSFER_BIT)) ||
      (format->aspect==VK_IMAGE_ASPECT_DEPTH_BIT && !(device->queue_flags&VK_QUEUE_GRAPHICS_BIT)))) code=BV_ARGUMENT;
  VkBufferImageCopy* regions=NULL;uint32_t count=0;Term list=f[4];
  while (term_aux(list)==CID(Con)) {
    Term item[2],p[12];bv_unpack(e,list,2,item);list=item[1];bv_unpack(e,item[0],12,p);
    if (code) continue;
    VkBufferImageCopy r={.bufferOffset=((uint64_t)(uint32_t)p[1]<<32)|(uint32_t)p[0],.bufferRowLength=p[2],.bufferImageHeight=p[3],
      .imageSubresource={p[4],p[5],p[6],p[7]},.imageOffset={(int32_t)(uint32_t)p[8],(int32_t)(uint32_t)p[9],0},.imageExtent={p[10],p[11],1}};
    BvImage* i=&image->object.image;uint32_t mip=r.imageSubresource.mipLevel;
    uint32_t w=bv_mip_dimension(i->extent.width,mip),h=bv_mip_dimension(i->extent.height,mip);uint64_t end,row;
    if (r.imageSubresource.aspectMask!=format->aspect || mip>=i->mips ||
        !bv_range_contains(i->layers,r.imageSubresource.baseArrayLayer,r.imageSubresource.layerCount) ||
        (uint32_t)p[8]>INT32_MAX || (uint32_t)p[9]>INT32_MAX || r.imageExtent.width>INT32_MAX || r.imageExtent.height>INT32_MAX ||
        (uint32_t)p[8]>w || r.imageExtent.width>w-(uint32_t)p[8] || (uint32_t)p[9]>h || r.imageExtent.height>h-(uint32_t)p[9] ||
        (r.bufferOffset&3) || !bv_copy_end(r.bufferOffset,r.bufferRowLength,r.bufferImageHeight,r.imageExtent.width,r.imageExtent.height,
          r.imageSubresource.layerCount,format->bytes,&end) || end>buffer->size ||
        !bv_mul64(r.bufferRowLength ? r.bufferRowLength : r.imageExtent.width,format->bytes,&row) || row>INT32_MAX) {code=BV_ARGUMENT;continue;}
    VkExtent3D g=device->queue_properties.minImageTransferGranularity;
    if (!bv_transfer_axis(p[8],r.imageExtent.width,w,g.width) || !bv_transfer_axis(p[9],r.imageExtent.height,h,g.height) ||
        !bv_transfer_axis(0,1,1,g.depth)) {code=BV_ARGUMENT;continue;}
    for (uint32_t j=0;j<count;j++) {
      VkBufferImageCopy a=regions[j];
      if (upload) {
        if (a.imageSubresource.mipLevel==mip && bv_overlap(a.imageSubresource.baseArrayLayer,a.imageSubresource.layerCount,r.imageSubresource.baseArrayLayer,r.imageSubresource.layerCount) &&
            bv_overlap(a.imageOffset.x,a.imageExtent.width,r.imageOffset.x,r.imageExtent.width) && bv_overlap(a.imageOffset.y,a.imageExtent.height,r.imageOffset.y,r.imageExtent.height)) code=BV_ARGUMENT;
      } else {
        uint64_t previous;bv_copy_end(a.bufferOffset,a.bufferRowLength,a.bufferImageHeight,a.imageExtent.width,a.imageExtent.height,a.imageSubresource.layerCount,format->bytes,&previous);
        if (bv_overlap(a.bufferOffset,previous-a.bufferOffset,r.bufferOffset,end-r.bufferOffset)) code=BV_ARGUMENT;
      }
    }
    if (code) continue;
    if (count>=4096) {code=BV_LIMIT;continue;}
    VkBufferImageCopy* more=realloc(regions,(count+1)*sizeof(*regions));
    if (!more) {code=BV_LIMIT;continue;}regions=more;regions[count++]=r;
  }
  if (!code && !count) code=BV_ARGUMENT;
  if (owner && bv_lost(owner)) {free(regions);return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"copy image buffer");}
  BvRow* roots[]={buffer,image};if (!code && !bv_prepare_refs(command,2,roots)) code=BV_LIMIT;
  if (!code) {
    if (upload) device->CmdCopyBufferToImage((VkCommandBuffer)(uintptr_t)command->handle,(VkBuffer)(uintptr_t)buffer->handle,(VkImage)(uintptr_t)image->handle,layout,count,regions);
    else device->CmdCopyImageToBuffer((VkCommandBuffer)(uintptr_t)command->handle,(VkImage)(uintptr_t)image->handle,layout,(VkBuffer)(uintptr_t)buffer->handle,count,regions);
  }
  free(regions);return code ? io_fail(e,code,"copy image buffer state, queue, layout, region, overlap or allocation") : bv_ok(e);
}
#endif
#ifdef CID(CommandBuffer.copy_buffer_to_image)
static Term bv_cmd_copy_buffer_to_image(Env e,Term* f,IoWork* w) {return bv_copy_image_buffer(e,f,1);}
#endif
#ifdef CID(CommandBuffer.copy_image_to_buffer)
static Term bv_cmd_copy_image_to_buffer(Env e,Term* f,IoWork* w) {return bv_copy_image_buffer(e,f,0);}
#endif

#ifdef CID(CommandBuffer.end)
static Term bv_end_command_buffer(Env e, Term* f, IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);
  if (!command) return io_fail(e,BV_INVALID,"invalid command buffer");
  if (bv_lost(bv_command_device(command))) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"bv_end_command_buffer");
  if (!bv_outside(command)) return io_fail(e,BV_LIFETIME,"command buffer is not recording");
  BvDevice* device=bv_command_device(command)->context;
  VkResult result=device->EndCommandBuffer((VkCommandBuffer)(uintptr_t)command->handle);
  if (result!=VK_SUCCESS) {command->command.phase=BV_COMMAND_INVALID;return bv_device_error(e,bv_command_device(command),result,"vkEndCommandBuffer");}
  command->command.phase=BV_EXECUTABLE;return bv_ok(e);
}
#endif
static uint32_t bv_new_fence(BvRow* owner,int signaled,BvFenceLifetime lifetime,BvRow** out,VkResult* status) {
  BvDevice* device=owner->context;
  VkFenceCreateInfo info={.sType=VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,.flags=signaled ? VK_FENCE_CREATE_SIGNALED_BIT : 0};
  VkFence handle; *status=bv_device_result(owner,device->CreateFence(device->handle,&info,NULL,&handle));
  if (*status!=VK_SUCCESS) return 0;
  BvRow* fence=bv_add(BV_FENCE,owner);
  if (!fence) {device->DestroyFence(device->handle,handle,NULL);return BV_LIMIT;}
  fence->handle=(uint64_t)(uintptr_t)handle;fence->fence.lifetime=lifetime;*out=fence;return 0;
}
static Term bv_submit_core(Env e,BvRow* owner,BvRow* command,BvRow* fence) {
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"submit");
  if (command->command.phase!=BV_EXECUTABLE || bv_active(owner,NULL)) return io_fail(e,BV_LIFETIME,"submit needs executable command and idle queue");
  BvDevice* device=owner->context;
  VkResult result=bv_device_result(owner,device->GetFenceStatus(device->handle,(VkFence)(uintptr_t)fence->handle));
  if (result==VK_SUCCESS) return io_fail(e,BV_LIFETIME,"submit fence must be unsignaled");
  if (result!=VK_NOT_READY) return bv_vk_error(e,result,"submit / vkGetFenceStatus");
  VkCommandBuffer handle=(VkCommandBuffer)(uintptr_t)command->handle;
  VkSubmitInfo submit={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&handle};
  result=bv_device_result(owner,device->QueueSubmit(device->queue,1,&submit,(VkFence)(uintptr_t)fence->handle));
  if (result==VK_SUCCESS) {
    command->command.phase=BV_PENDING;command->command.submission.pending.fence=fence;
  } else if (result!=VK_ERROR_OUT_OF_HOST_MEMORY && result!=VK_ERROR_OUT_OF_DEVICE_MEMORY && result!=VK_ERROR_DEVICE_LOST) {
    command->command.phase=BV_UNCERTAIN;command->command.submission.uncertain.fence=fence;
  }
  return result==VK_SUCCESS ? bv_ok(e) : bv_vk_error(e,result,"vkQueueSubmit");
}
static Term bv_fence_observe(Env e,BvRow* fence,int wait,uint64_t timeout) {
  BvRow* owner=fence->parent;BvDevice* device=owner->context;
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"fence observation");
  BvRow* command=bv_active(owner,fence);
  if (command && command->command.phase==BV_UNCERTAIN) return io_fail(e,BV_LIFETIME,"uncertain submission requires Device.wait_idle");
  VkFence handle=(VkFence)(uintptr_t)fence->handle;
  VkResult result=bv_device_result(owner,wait ? device->WaitForFences(device->handle,1,&handle,VK_TRUE,timeout) : device->GetFenceStatus(device->handle,handle));
  if (result==VK_SUCCESS && command) bv_complete(command);
  if (result==VK_SUCCESS || result==(wait ? VK_TIMEOUT : VK_NOT_READY)) return io_done(e,(uint32_t)result);
  return bv_vk_error(e,result,wait ? "vkWaitForFences" : "vkGetFenceStatus");
}
#ifdef CID(Device.create_fence)
static Term bv_create_fence(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  if (!owner) return io_fail(e,BV_INVALID,"invalid device");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"create_fence");
  BvRow* fence=NULL;VkResult status=VK_SUCCESS;
  uint32_t code=bv_new_fence(owner,term_aux(f[1])==CID(True),BV_CALLER,&fence,&status);
  if (code) return io_fail(e,code,"fence registry full");
  return status==VK_SUCCESS ? io_done(e,term_pak(CID(Fence),fence->id)) : bv_vk_error(e,status,"vkCreateFence");
}
#endif
#ifdef CID(Device.destroy_fence)
static Term bv_destroy_fence(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);BvRow* fence=bv_public_fence(bv_key(e,f[1]));
  if (!owner || !fence || fence->parent!=owner) return io_fail(e,BV_INVALID,"invalid fence or device");
  if (bv_active(owner,fence)) return io_fail(e,BV_LIFETIME,"fence has active submission");
  BvDevice* device=owner->context;device->DestroyFence(device->handle,(VkFence)(uintptr_t)fence->handle,NULL);
  bv_remove(fence);return bv_ok(e);
}
#endif
#ifdef CID(Device.submit)
static Term bv_submit(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);BvRow* command=bv_get(bv_key(e,f[1]),BV_COMMAND);
  BvRow* fence=bv_public_fence(bv_key(e,f[2]));
  if (!owner || bv_command_device(command)!=owner || !fence || fence->parent!=owner) return io_fail(e,BV_INVALID,"submit ownership mismatch");
  return bv_submit_core(e,owner,command,fence);
}
#endif
#ifdef CID(Fence.status)
static Term bv_fence_status(Env e,Term* f,IoWork* w) {
  BvRow* fence=bv_public_fence(bv_key(e,f[0]));
  return fence ? bv_fence_observe(e,fence,0,0) : io_fail(e,BV_INVALID,"invalid public fence");
}
#endif
#ifdef CID(Fence.wait)
static Term bv_fence_wait(Env e,Term* f,IoWork* w) {
  BvRow* fence=bv_public_fence(bv_key(e,f[0]));uint64_t timeout=bv_u64(e,f[1]);
  return fence ? bv_fence_observe(e,fence,1,timeout) : io_fail(e,BV_INVALID,"invalid public fence");
}
#endif
static Term bv_reset_fence_core(Env e,BvRow* fence) {
  BvRow* owner=fence->parent;BvDevice* device=owner->context;
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"fence reset");
  if (bv_active(owner,fence)) return io_fail(e,BV_LIFETIME,"fence has active submission");
  VkFence handle=(VkFence)(uintptr_t)fence->handle;
  VkResult result=bv_device_result(owner,device->ResetFences(device->handle,1,&handle));
  return result==VK_SUCCESS ? bv_ok(e) : bv_vk_error(e,result,"vkResetFences");
}
#ifdef CID(Fence.reset)
static Term bv_fence_reset(Env e,Term* f,IoWork* w) {
  BvRow* fence=bv_public_fence(bv_key(e,f[0]));
  return fence ? bv_reset_fence_core(e,fence) : io_fail(e,BV_INVALID,"invalid public fence");
}
#endif
#ifdef CID(CommandBuffer.reset)
static Term bv_reset_command_buffer(Env e,Term* f,IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);
  if (!command) return io_fail(e,BV_INVALID,"invalid command buffer");
  BvRow* owner=bv_command_device(command);BvDevice* device=owner->context;
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"command reset");
  if (bv_command_fence(command)) return io_fail(e,BV_LIFETIME,"command has active submission");
  VkResult result=bv_device_result(owner,device->ResetCommandBuffer((VkCommandBuffer)(uintptr_t)command->handle,0));
  command->command.phase=result==VK_SUCCESS ? BV_INITIAL : BV_COMMAND_INVALID;
  memset(&command->command.submission,0,sizeof(command->command.submission));
  if (result!=VK_SUCCESS) return bv_vk_error(e,result,"vkResetCommandBuffer");
  bv_free_refs(command->deps);command->deps=NULL;return bv_ok(e);
}
#endif
#ifdef CID(Device.submit_and_wait)
static Term bv_submit_and_wait(Env e,Term* f,IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);BvRow* command=bv_get(bv_key(e,f[1]),BV_COMMAND);
  if (!owner || bv_command_device(command)!=owner) return io_fail(e,BV_INVALID,"invalid command buffer or device");
  if (bv_lost(owner)) return bv_vk_error(e,VK_ERROR_DEVICE_LOST,"submit_and_wait");
  if (command->command.phase!=BV_EXECUTABLE || bv_active(owner,NULL)) return io_fail(e,BV_LIFETIME,"submit needs executable command and idle queue");
  BvDevice* device=owner->context;Term result;
  if (!device->convenience) {
    VkResult status=VK_SUCCESS;uint32_t code=bv_new_fence(owner,0,BV_CONVENIENCE_PRIVATE,&device->convenience,&status);
    if (code) return io_fail(e,code,"private fence registry full");
    if (status!=VK_SUCCESS) return bv_vk_error(e,status,"vkCreateFence / convenience");
  } else {
    result=bv_reset_fence_core(e,device->convenience);
    if (term_aux(result)==CID(Fail)) return result;
    term_sink(e,result);
  }
  result=bv_submit_core(e,owner,command,device->convenience);
  if (term_aux(result)==CID(Fail)) return result;
  term_sink(e,result);
  result=bv_fence_observe(e,device->convenience,1,UINT64_MAX);
  if (term_aux(result)==CID(Fail)) return result;
  Term status[1];bv_unpack(e,result,1,status);
  return (uint32_t)status[0]==VK_SUCCESS ? bv_ok(e) : bv_vk_error(e,(VkResult)(uint32_t)status[0],"submit_and_wait / incomplete infinite wait");
}
#endif
#ifdef CID(debug_live_objects)
static Term bv_live_objects(Env e, Term* f, IoWork* w) {
  uint32_t count=0;for (BvRow* row=bv_rows;row;row=row->next) count++;
  return io_done(e,count);
}
#endif
#ifdef CID(debug_u64_roundtrip)
static Term bv_u64_roundtrip(Env e, Term* f, IoWork* w) {
  return io_done(e,bv_words(e,bv_u64(e,f[0])));
}
#endif

static void __attribute__((constructor)) bv_register(void) {
// BEGIN GENERATED REGISTRATIONS
#ifdef CID(Entry.load)
  io_eff(CID(Entry.load), bv_entry_load);
#endif
#ifdef CID(Entry.close)
  io_eff(CID(Entry.close), bv_entry_close);
#endif
#ifdef CID(Entry.enumerate_instance_version)
  io_eff(CID(Entry.enumerate_instance_version), bv_entry_version);
#endif
#ifdef CID(Entry.create_instance)
  io_eff(CID(Entry.create_instance), bv_create_instance);
#endif
#ifdef CID(Instance.destroy)
  io_eff(CID(Instance.destroy), bv_destroy_instance_effect);
#endif
#ifdef CID(Instance.enumerate_physical_devices)
  io_eff(CID(Instance.enumerate_physical_devices), bv_enumerate_physical_devices);
#endif
#ifdef CID(Instance.get_physical_device_properties)
  io_eff(CID(Instance.get_physical_device_properties), bv_physical_properties);
#endif
#ifdef CID(Instance.get_physical_device_queue_family_properties)
  io_eff(CID(Instance.get_physical_device_queue_family_properties), bv_queue_properties);
#endif
#ifdef CID(Instance.memory_types_raw)
  io_eff(CID(Instance.memory_types_raw), bv_memory_types);
#endif
#ifdef CID(Instance.create_device)
  io_eff(CID(Instance.create_device), bv_create_device);
#endif
#ifdef CID(Device.destroy)
  io_eff(CID(Device.destroy), bv_destroy_device_effect);
#endif
#ifdef CID(Device.wait_idle)
  io_eff(CID(Device.wait_idle), bv_device_wait_idle);
#endif
#ifdef CID(Device.create_buffer)
  io_eff(CID(Device.create_buffer), bv_create_buffer);
#endif
#ifdef CID(Device.destroy_buffer)
  io_eff(CID(Device.destroy_buffer), bv_destroy_buffer);
#endif
#ifdef CID(Device.buffer_requirements_raw)
  io_eff(CID(Device.buffer_requirements_raw), bv_buffer_requirements);
#endif
#ifdef CID(Device.allocate_memory)
  io_eff(CID(Device.allocate_memory), bv_allocate_memory);
#endif
#ifdef CID(Device.free_memory)
  io_eff(CID(Device.free_memory), bv_free_memory);
#endif
#ifdef CID(Device.bind_buffer_memory)
  io_eff(CID(Device.bind_buffer_memory), bv_bind_buffer_memory);
#endif
#ifdef CID(Device.write_memory)
  io_eff(CID(Device.write_memory), bv_write_memory);
#endif
#ifdef CID(Device.write_memory_words)
  io_eff(CID(Device.write_memory_words), bv_write_memory_words);
#endif
#ifdef CID(Device.read_memory)
  io_eff(CID(Device.read_memory), bv_read_memory);
#endif
#ifdef CID(Device.create_command_pool)
  io_eff(CID(Device.create_command_pool), bv_create_command_pool);
#endif
#ifdef CID(Device.destroy_command_pool)
  io_eff(CID(Device.destroy_command_pool), bv_destroy_command_pool);
#endif
#ifdef CID(Device.allocate_command_buffer)
  io_eff(CID(Device.allocate_command_buffer), bv_allocate_command_buffer);
#endif
#ifdef CID(CommandBuffer.begin)
  io_eff(CID(CommandBuffer.begin), bv_begin_command_buffer);
#endif
#ifdef CID(CommandBuffer.fill_buffer)
  io_eff(CID(CommandBuffer.fill_buffer), bv_cmd_fill_buffer);
#endif
#ifdef CID(CommandBuffer.copy_buffer)
  io_eff(CID(CommandBuffer.copy_buffer), bv_cmd_copy_buffer);
#endif
#ifdef CID(CommandBuffer.pipeline_barrier)
  io_eff(CID(CommandBuffer.pipeline_barrier), bv_cmd_pipeline_barrier);
#endif
#ifdef CID(CommandBuffer.end)
  io_eff(CID(CommandBuffer.end), bv_end_command_buffer);
#endif
#ifdef CID(Device.submit_and_wait)
  io_eff(CID(Device.submit_and_wait), bv_submit_and_wait);
#endif
#ifdef CID(debug_live_objects)
  io_eff(CID(debug_live_objects), bv_live_objects);
#endif
#ifdef CID(debug_u64_roundtrip)
  io_eff(CID(debug_u64_roundtrip), bv_u64_roundtrip);
#endif
#ifdef CID(Device.create_fence)
  io_eff(CID(Device.create_fence), bv_create_fence);
#endif
#ifdef CID(Device.destroy_fence)
  io_eff(CID(Device.destroy_fence), bv_destroy_fence);
#endif
#ifdef CID(Device.submit)
  io_eff(CID(Device.submit), bv_submit);
#endif
#ifdef CID(Fence.status)
  io_eff(CID(Fence.status), bv_fence_status);
#endif
#ifdef CID(Fence.wait)
  io_eff(CID(Fence.wait), bv_fence_wait);
#endif
#ifdef CID(Fence.reset)
  io_eff(CID(Fence.reset), bv_fence_reset);
#endif
#ifdef CID(CommandBuffer.reset)
  io_eff(CID(CommandBuffer.reset), bv_reset_command_buffer);
#endif
#ifdef CID(Entry.enumerate_instance_layers)
  io_eff(CID(Entry.enumerate_instance_layers), bv_instance_layers);
#endif
#ifdef CID(Entry.enumerate_instance_extensions)
  io_eff(CID(Entry.enumerate_instance_extensions), bv_instance_extensions);
#endif
#ifdef CID(Instance.enumerate_device_extensions)
  io_eff(CID(Instance.enumerate_device_extensions), bv_device_extensions);
#endif
#ifdef CID(Instance.memory_heaps_raw)
  io_eff(CID(Instance.memory_heaps_raw), bv_memory_heaps);
#endif
#ifdef CID(Instance.get_physical_device_format_properties)
  io_eff(CID(Instance.get_physical_device_format_properties), bv_format_properties);
#endif
#ifdef CID(Instance.limits_raw)
  io_eff(CID(Instance.limits_raw), bv_physical_limits);
#endif
#ifdef CID(Instance.image_format_properties_raw)
  io_eff(CID(Instance.image_format_properties_raw), bv_image_format_properties);
#endif
#ifdef CID(Device.create_image)
  io_eff(CID(Device.create_image), bv_create_image);
#endif
#ifdef CID(Device.destroy_image)
  io_eff(CID(Device.destroy_image), bv_destroy_image);
#endif
#ifdef CID(Device.image_requirements_raw)
  io_eff(CID(Device.image_requirements_raw), bv_image_requirements);
#endif
#ifdef CID(Device.bind_image_memory)
  io_eff(CID(Device.bind_image_memory), bv_bind_image_memory);
#endif
#ifdef CID(Device.create_image_view)
  io_eff(CID(Device.create_image_view), bv_create_image_view);
#endif
#ifdef CID(Device.destroy_image_view)
  io_eff(CID(Device.destroy_image_view), bv_destroy_image_view);
#endif
#ifdef CID(CommandBuffer.clear_color_image)
  io_eff(CID(CommandBuffer.clear_color_image), bv_cmd_clear_color_image);
#endif
#ifdef CID(CommandBuffer.clear_depth_image)
  io_eff(CID(CommandBuffer.clear_depth_image), bv_cmd_clear_depth_image);
#endif
#ifdef CID(CommandBuffer.copy_buffer_to_image)
  io_eff(CID(CommandBuffer.copy_buffer_to_image), bv_cmd_copy_buffer_to_image);
#endif
#ifdef CID(CommandBuffer.copy_image_to_buffer)
  io_eff(CID(CommandBuffer.copy_image_to_buffer), bv_cmd_copy_image_to_buffer);
#endif
#ifdef CID(Device.create_render_pass)
  io_eff(CID(Device.create_render_pass), bv_create_render_pass);
#endif
#ifdef CID(Device.destroy_render_pass)
  io_eff(CID(Device.destroy_render_pass), bv_destroy_render_pass);
#endif
#ifdef CID(Device.create_framebuffer)
  io_eff(CID(Device.create_framebuffer), bv_create_framebuffer);
#endif
#ifdef CID(Device.destroy_framebuffer)
  io_eff(CID(Device.destroy_framebuffer), bv_destroy_framebuffer);
#endif
#ifdef CID(CommandBuffer.begin_render_pass)
  io_eff(CID(CommandBuffer.begin_render_pass), bv_cmd_begin_render_pass);
#endif
#ifdef CID(CommandBuffer.end_render_pass)
  io_eff(CID(CommandBuffer.end_render_pass), bv_cmd_end_render_pass);
#endif
// END GENERATED REGISTRATIONS
}
