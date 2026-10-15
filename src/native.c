// Bend 2.0.37 effect ABI. Only the IO event loop accesses the registry.
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <limits.h>

#if !defined(__linux__) || UINTPTR_MAX != UINT64_MAX
#error "bend-vulkan currently requires 64-bit Linux"
#endif

#define BV_INVALID 0x60000002u
#define BV_ARGUMENT 0x60000003u
#define BV_LIFETIME 0x60000004u
#define BV_LIMIT 0x60000005u
#define BV_MAX_COPY (16u * 1024u * 1024u)

typedef enum { BV_ENTRY, BV_INSTANCE, BV_PHYSICAL, BV_DEVICE, BV_BUFFER,
  BV_MEMORY, BV_POOL, BV_COMMAND } BvKind;
typedef struct BvRow BvRow;
typedef struct BvUse { BvRow* resource; struct BvUse* next; } BvUse;
struct BvRow {
  uint32_t id;
  BvKind kind;
  BvRow *parent, *next, *bound;
  uint64_t handle, size, offset;
  uint32_t flags, state;
  void* context;
  BvUse* uses;
};
static BvRow* bv_rows;
static uint32_t bv_next_id = 1;

typedef struct {
  void* library;
  PFN_vkGetInstanceProcAddr get;
  PFN_vkCreateInstance create;
  PFN_vkEnumerateInstanceVersion version;
} BvEntry;

typedef struct {
  VkInstance handle;
  PFN_vkDestroyInstance destroy;
  PFN_vkEnumeratePhysicalDevices enumerate;
  PFN_vkGetPhysicalDeviceProperties properties;
  PFN_vkGetPhysicalDeviceQueueFamilyProperties queues;
  PFN_vkGetPhysicalDeviceMemoryProperties memory;
  PFN_vkCreateDevice create_device;
  PFN_vkGetDeviceProcAddr get_device;
} BvInstance;

#define BV_DEVICE_FUNCTIONS(X) \
  X(DestroyDevice) X(DeviceWaitIdle) X(GetDeviceQueue) \
  X(CreateBuffer) X(DestroyBuffer) X(GetBufferMemoryRequirements) \
  X(AllocateMemory) X(FreeMemory) X(BindBufferMemory) X(MapMemory) X(UnmapMemory) \
  X(FlushMappedMemoryRanges) X(InvalidateMappedMemoryRanges) \
  X(CreateCommandPool) X(DestroyCommandPool) X(AllocateCommandBuffers) \
  X(BeginCommandBuffer) X(EndCommandBuffer) X(CmdFillBuffer) \
  X(CmdCopyBuffer) X(CmdPipelineBarrier) X(QueueSubmit) X(QueueWaitIdle)
typedef struct {
  VkDevice handle;
  VkPhysicalDevice physical;
  VkQueue queue;
  uint32_t family, queue_flags;
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
  while (row->uses) { BvUse* use = row->uses; row->uses = use->next; free(use); }
  free(row);
}
static BvRow* bv_child(uint32_t id, BvKind kind, BvRow* owner) {
  BvRow* row = bv_get(id, kind);
  return row && row->parent == owner ? row : NULL;
}
static BvRow* bv_command_device(BvRow* command) {
  return command ? command->parent->parent : NULL;
}
static int bv_referenced(BvRow* buffer) {
  for (BvRow* row = bv_rows; row; row = row->next)
    for (BvUse* use = row->uses; use; use = use->next)
      if (use->resource == buffer) return 1;
  return 0;
}
static void bv_free_refs(BvUse* uses) {
  while (uses) { BvUse* next=uses->next; free(uses); uses=next; }
}
static int bv_prepare_refs(BvRow* command, uint32_t count, BvRow** resources) {
  BvUse* staged=NULL;
  for (uint32_t j=0;j<count;j++) {
    int found=0;
    for (BvUse* u=command->uses;u;u=u->next) found |= u->resource==resources[j];
    for (BvUse* u=staged;u;u=u->next) found |= u->resource==resources[j];
    if (found) continue;
    BvUse* use=malloc(sizeof(*use));
    if (!use) { bv_free_refs(staged); return 0; }
    use->resource=resources[j]; use->next=staged; staged=use;
  }
  while (staged) {
    BvUse* next=staged->next; staged->next=command->uses; command->uses=staged; staged=next;
  }
  return 1;
}

// Optional geometry and tessellation features are never enabled by create_device.
static uint32_t bv_stages(BvDevice* device, uint32_t mask) {
  const uint32_t graphics=VK_PIPELINE_STAGE_VERTEX_INPUT_BIT|VK_PIPELINE_STAGE_VERTEX_SHADER_BIT|
    VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT|VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT|
    VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT|VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  uint32_t allowed=VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT|VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT|VK_PIPELINE_STAGE_HOST_BIT;
  if (device->queue_flags & VK_QUEUE_GRAPHICS_BIT) allowed |= graphics;
  if (device->queue_flags & VK_QUEUE_COMPUTE_BIT) allowed |= VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
  if (device->queue_flags & (VK_QUEUE_GRAPHICS_BIT|VK_QUEUE_COMPUTE_BIT)) allowed |= VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT;
  if (device->queue_flags & (VK_QUEUE_GRAPHICS_BIT|VK_QUEUE_COMPUTE_BIT|VK_QUEUE_TRANSFER_BIT)) allowed |= VK_PIPELINE_STAGE_TRANSFER_BIT;
  if (!mask || (mask & ~(allowed|VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT|VK_PIPELINE_STAGE_ALL_COMMANDS_BIT))) return 0;
  uint32_t expanded=mask & allowed;
  if (mask & VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT) {
    if (!(device->queue_flags & VK_QUEUE_GRAPHICS_BIT)) return 0;
    expanded |= graphics|VK_PIPELINE_STAGE_DRAW_INDIRECT_BIT;
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
  // There are no asynchronous submissions in this initial API.
  for (;;) {
    BvRow* pool = NULL;
    for (BvRow* child = bv_rows; child; child = child->next)
      if (child->parent == row && child->kind == BV_POOL) { pool = child; break; }
    if (!pool) break;
    bv_destroy_pool(pool);
  }
  for (BvRow* child = bv_rows, *next; child; child = next) {
    next = child->next;
    if (child->parent == row && child->kind == BV_BUFFER) {
      device->DestroyBuffer(device->handle, (VkBuffer)(uintptr_t)child->handle, NULL);
      bv_remove(child);
    }
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
  }
  if (!entry->get || !entry->create) {
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
    BvDevice* device = found->context;
    VkResult result = device->DeviceWaitIdle(device->handle);
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
  BV_INSTANCE_LOAD(create_device, CreateDevice);
  BV_INSTANCE_LOAD(get_device, GetDeviceProcAddr);
#undef BV_INSTANCE_LOAD
  BvRow* row = NULL;
  if (destroy && instance->enumerate && instance->properties && instance->queues &&
      instance->memory && instance->create_device && instance->get_device) row=bv_add(BV_INSTANCE, owner);
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
  uint32_t queue_flags=queues[(uint32_t)info[0]].queueFlags;free(queues);
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
  context->handle=device;context->physical=handle;context->family=(uint32_t)info[0];context->queue_flags=queue_flags;
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
  if (bv_has_children(row,BV_ENTRY)) return io_fail(e,BV_LIFETIME,"device still has resources");
  BvDevice* device=row->context;VkResult result=device->DeviceWaitIdle(device->handle);
  if (result!=VK_SUCCESS) return bv_vk_error(e,result,"vkDeviceWaitIdle");
  bv_destroy_device(row);return bv_ok(e);
}
#endif
#ifdef CID(Device.wait_idle)
static Term bv_device_wait_idle(Env e, Term* f, IoWork* w) {
  BvRow* row=bv_get(bv_key(e,f[0]),BV_DEVICE);
  if (!row) return io_fail(e,BV_INVALID,"invalid device");
  BvDevice* device=row->context;VkResult result=device->DeviceWaitIdle(device->handle);
  if (result==VK_SUCCESS || result==VK_ERROR_DEVICE_LOST) row->state=0;
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
  BvDevice* device=owner->context;
  VkBufferCreateInfo create={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
    .size=size,.usage=(uint32_t)info[2],.sharingMode=VK_SHARING_MODE_EXCLUSIVE};
  VkBuffer buffer;VkResult result=device->CreateBuffer(device->handle,&create,NULL,&buffer);
  if (result!=VK_SUCCESS) return bv_vk_error(e,result,"vkCreateBuffer");
  BvRow* row=bv_add(BV_BUFFER,owner);
  if (!row) {device->DestroyBuffer(device->handle,buffer,NULL);return io_fail(e,BV_LIMIT,"buffer registry full");}
  row->handle=(uint64_t)(uintptr_t)buffer;row->size=size;row->flags=(uint32_t)info[2];
  return io_done(e,term_pak(CID(Buffer),row->id));
}
#endif
#ifdef CID(Device.destroy_buffer)
static Term bv_destroy_buffer(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* buffer=bv_child(bv_key(e,f[1]),BV_BUFFER,owner);
  if (!owner || !buffer) return io_fail(e,BV_INVALID,"invalid buffer or device");
  if (owner->state) return io_fail(e,BV_LIFETIME,"call Device.wait_idle after a failed queue wait");
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
  BvDevice* device=owner->context;VkMemoryRequirements requirements;
  device->GetBufferMemoryRequirements(device->handle,(VkBuffer)(uintptr_t)buffer->handle,&requirements);
  return io_done(e,io_tup(e,bv_words(e,requirements.size),
    io_tup(e,bv_words(e,requirements.alignment),requirements.memoryTypeBits)));
}
#endif
#ifdef CID(Device.allocate_memory)
static Term bv_allocate_memory(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);uint64_t size=bv_u64(e,f[1]);
  if (!owner) return io_fail(e,BV_INVALID,"invalid device");
  BvDevice* device=owner->context;uint32_t index=(uint32_t)f[2];
  if (!size || index>=device->memory.memoryTypeCount) return io_fail(e,BV_ARGUMENT,"invalid allocation size or memory type");
  VkMemoryAllocateInfo info={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=size,.memoryTypeIndex=index};
  VkDeviceMemory memory;VkResult result=device->AllocateMemory(device->handle,&info,NULL,&memory);
  if (result!=VK_SUCCESS) return bv_vk_error(e,result,"vkAllocateMemory");
  BvRow* row=bv_add(BV_MEMORY,owner);
  if (!row) {device->FreeMemory(device->handle,memory,NULL);return io_fail(e,BV_LIMIT,"memory registry full");}
  row->handle=(uint64_t)(uintptr_t)memory;row->size=size;
  row->flags=device->memory.memoryTypes[index].propertyFlags;row->state=index;
  return io_done(e,term_pak(CID(DeviceMemory),row->id));
}
#endif
#ifdef CID(Device.free_memory)
static Term bv_free_memory(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* memory=bv_child(bv_key(e,f[1]),BV_MEMORY,owner);
  if (!owner || !memory) return io_fail(e,BV_INVALID,"invalid memory or device");
  if (owner->state) return io_fail(e,BV_LIFETIME,"call Device.wait_idle after a failed queue wait");
  for (BvRow* row=bv_rows;row;row=row->next)
    if (row->bound==memory) return io_fail(e,BV_LIFETIME,"destroy bound buffers before freeing memory");
  BvDevice* device=owner->context;
  device->FreeMemory(device->handle,(VkDeviceMemory)(uintptr_t)memory->handle,NULL);
  bv_remove(memory);return bv_ok(e);
}
#endif
#ifdef CID(Device.bind_buffer_memory)
static Term bv_bind_buffer_memory(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* buffer=bv_child(bv_key(e,f[1]),BV_BUFFER,owner);
  BvRow* memory=bv_child(bv_key(e,f[2]),BV_MEMORY,owner);uint64_t offset=bv_u64(e,f[3]);
  if (!owner || !buffer || !memory) return io_fail(e,BV_INVALID,"buffer and memory must belong to device");
  if (buffer->bound) return io_fail(e,BV_LIFETIME,"buffer is already bound");
  BvDevice* device=owner->context;VkMemoryRequirements requirements;
  device->GetBufferMemoryRequirements(device->handle,(VkBuffer)(uintptr_t)buffer->handle,&requirements);
  if (offset>memory->size || requirements.size>memory->size-offset || offset%requirements.alignment ||
      !(requirements.memoryTypeBits & (1u<<memory->state)))
    return io_fail(e,BV_ARGUMENT,"memory binding violates size, alignment, or memory type requirements");
  VkResult result=device->BindBufferMemory(device->handle,(VkBuffer)(uintptr_t)buffer->handle,
    (VkDeviceMemory)(uintptr_t)memory->handle,offset);
  if (result!=VK_SUCCESS) return bv_vk_error(e,result,"vkBindBufferMemory");
  buffer->bound=memory;buffer->offset=offset;return bv_ok(e);
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
  if (owner->state) {free(bytes);return io_fail(e,BV_LIFETIME,"call Device.wait_idle after a failed queue wait");}
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
  free(bytes);return result==VK_SUCCESS ? bv_ok(e) : bv_vk_error(e,result,"write_memory / map or flush");
}
#endif
#ifdef CID(Device.write_memory_words)
static Term bv_write_memory_words(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* memory=bv_child(bv_key(e,f[1]),BV_MEMORY,owner);
  uint64_t offset=bv_u64(e,f[2]), count=bv_u64(e,f[3]); Term words=f[4], result;
  if (!owner || !memory) result=io_fail(e,BV_INVALID,"write_memory_words: invalid device or memory");
  else if (owner->state) result=io_fail(e,BV_LIFETIME,"write_memory_words: unresolved work");
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
    result=status==VK_SUCCESS ? bv_ok(e) : bv_vk_error(e,status,"write_memory_words / map or flush");
  }
  return io_tup(e,words,result);
}
#endif
#ifdef CID(Device.read_memory)
static Term bv_read_memory(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  BvRow* memory=bv_child(bv_key(e,f[1]),BV_MEMORY,owner);uint64_t offset=bv_u64(e,f[2]);uint32_t count=(uint32_t)f[3];
  if (!owner || !memory) return io_fail(e,BV_INVALID,"invalid memory or device");
  if (owner->state) return io_fail(e,BV_LIFETIME,"call Device.wait_idle after a failed queue wait");
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
  return result==VK_SUCCESS ? io_done(e,list) : bv_vk_error(e,result,"read_memory / map or invalidate");
}
#endif
#ifdef CID(Device.create_command_pool)
static Term bv_create_command_pool(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);
  if (!owner) return io_fail(e,BV_INVALID,"invalid device");
  BvDevice* device=owner->context;
  if (!(device->queue_flags & (VK_QUEUE_GRAPHICS_BIT|VK_QUEUE_COMPUTE_BIT|VK_QUEUE_TRANSFER_BIT)))
    return io_fail(e,BV_ARGUMENT,"command pool needs a transfer-capable queue family");
  VkCommandPoolCreateInfo info={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,.queueFamilyIndex=device->family};
  VkCommandPool pool;VkResult result=device->CreateCommandPool(device->handle,&info,NULL,&pool);
  if (result!=VK_SUCCESS) return bv_vk_error(e,result,"vkCreateCommandPool");
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
  if (owner->state) return io_fail(e,BV_LIFETIME,"call Device.wait_idle after a failed queue wait");
  bv_destroy_pool(pool);return bv_ok(e);
}
#endif
#ifdef CID(Device.allocate_command_buffer)
static Term bv_allocate_command_buffer(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);BvRow* pool=bv_child(bv_key(e,f[1]),BV_POOL,owner);
  if (!owner || !pool) return io_fail(e,BV_INVALID,"invalid command pool or device");
  BvDevice* device=owner->context;BvRow* row=bv_add(BV_COMMAND,pool);
  if (!row) return io_fail(e,BV_LIMIT,"command buffer registry full");
  VkCommandBufferAllocateInfo info={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
    .commandPool=(VkCommandPool)(uintptr_t)pool->handle,.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY,.commandBufferCount=1};
  VkCommandBuffer command;VkResult result=device->AllocateCommandBuffers(device->handle,&info,&command);
  if (result!=VK_SUCCESS) {bv_remove(row);return bv_vk_error(e,result,"vkAllocateCommandBuffers");}
  row->handle=(uint64_t)(uintptr_t)command;
  return io_done(e,term_pak(CID(CommandBuffer),row->id));
}
#endif
#ifdef CID(CommandBuffer.begin)
static Term bv_begin_command_buffer(Env e, Term* f, IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);
  if (!command) return io_fail(e,BV_INVALID,"invalid command buffer");
  if (command->state) return io_fail(e,BV_LIFETIME,"command buffer is one-shot and already begun");
  BvDevice* device=bv_command_device(command)->context;
  VkCommandBufferBeginInfo info={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT};
  VkResult result=device->BeginCommandBuffer((VkCommandBuffer)(uintptr_t)command->handle,&info);
  if (result!=VK_SUCCESS) {command->state=4;return bv_vk_error(e,result,"vkBeginCommandBuffer");}
  command->state=1;return bv_ok(e);
}
#endif
#ifdef CID(CommandBuffer.fill_buffer)
static Term bv_cmd_fill_buffer(Env e, Term* f, IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);uint32_t id=bv_key(e,f[1]);
  uint64_t offset=bv_u64(e,f[2]),size=bv_u64(e,f[3]);
  BvRow* owner=bv_command_device(command);BvRow* buffer=bv_child(id,BV_BUFFER,owner);
  if (!command || !buffer) return io_fail(e,BV_INVALID,"command and buffer must belong to same device");
  if (command->state!=1 || !buffer->bound) return io_fail(e,BV_LIFETIME,"fill needs recording command and bound buffer");
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
    (command->state!=1 || !src->bound || !dst->bound) ? BV_LIFETIME :
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
          (src->bound==dst->bound && bv_overlap(src->offset+regions[j].srcOffset,regions[j].size,
            dst->offset+regions[k].dstOffset,regions[k].size))) {code=BV_ARGUMENT;break;}
    }
  }
  BvRow* resources[]={src,dst};
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
  uint32_t src=device ? bv_stages(device,(uint32_t)f[1]) : 0;
  uint32_t dst=device ? bv_stages(device,(uint32_t)f[2]) : 0;
  uint32_t code=!command ? BV_INVALID : command->state!=1 ? BV_LIFETIME : (!src || !dst) ? BV_ARGUMENT : 0;
  VkMemoryBarrier* memory=NULL; VkBufferMemoryBarrier* buffers=NULL; BvRow** resources=NULL;
  uint32_t nm=0,nb=0; Term list=f[3];
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
    if (!buffer->bound) {code=BV_LIFETIME;continue;}
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
  if (!code && !bv_prepare_refs(command,nb,resources)) code=BV_LIMIT;
  if (!code) device->CmdPipelineBarrier((VkCommandBuffer)(uintptr_t)command->handle,
    (uint32_t)f[1],(uint32_t)f[2],0,nm,memory,nb,buffers,0,NULL);
  free(memory);free(buffers);free(resources);
  return code ? io_fail(e,code,"pipeline_barrier: invalid state, stages, access, range, or allocation") : bv_ok(e);
}
#endif
#ifdef CID(CommandBuffer.end)
static Term bv_end_command_buffer(Env e, Term* f, IoWork* w) {
  BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);
  if (!command) return io_fail(e,BV_INVALID,"invalid command buffer");
  if (command->state!=1) return io_fail(e,BV_LIFETIME,"command buffer is not recording");
  BvDevice* device=bv_command_device(command)->context;
  VkResult result=device->EndCommandBuffer((VkCommandBuffer)(uintptr_t)command->handle);
  if (result!=VK_SUCCESS) {command->state=4;return bv_vk_error(e,result,"vkEndCommandBuffer");}
  command->state=2;return bv_ok(e);
}
#endif
#ifdef CID(Device.submit_and_wait)
static Term bv_submit_and_wait(Env e, Term* f, IoWork* w) {
  BvRow* owner=bv_get(bv_key(e,f[0]),BV_DEVICE);BvRow* command=bv_get(bv_key(e,f[1]),BV_COMMAND);
  if (!owner || bv_command_device(command)!=owner) return io_fail(e,BV_INVALID,"invalid command buffer or device");
  if (owner->state) return io_fail(e,BV_LIFETIME,"call Device.wait_idle after a failed queue wait");
  if (command->state!=2) return io_fail(e,BV_LIFETIME,"submit needs an executable command buffer");
  BvDevice* device=owner->context;VkCommandBuffer handle=(VkCommandBuffer)(uintptr_t)command->handle;
  VkSubmitInfo submit={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&handle};
  // A failed submission is conservatively treated as requiring completion too.
  command->state=3;
  owner->state=1;
  VkResult result=device->QueueSubmit(device->queue,1,&submit,VK_NULL_HANDLE);
  if (result!=VK_SUCCESS) {
    if (result==VK_ERROR_DEVICE_LOST) owner->state=0;
    return bv_vk_error(e,result,"vkQueueSubmit");
  }
  result=device->QueueWaitIdle(device->queue);
  if (result==VK_SUCCESS || result==VK_ERROR_DEVICE_LOST) owner->state=0;
  return result==VK_SUCCESS ? bv_ok(e) : bv_vk_error(e,result,"vkQueueWaitIdle");
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
// END GENERATED REGISTRATIONS
}
