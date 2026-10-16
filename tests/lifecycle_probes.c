static void descriptor_add_cleanup_graph(Env e,BvRow* owner,BvRow* command);
static VkResult bv_test_submit_result, bv_test_wait_result, bv_test_idle_result;
static unsigned bv_test_submit_calls,bv_test_wait_calls;
static uint64_t bv_test_timeout;
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_submit(VkQueue q,uint32_t n,const VkSubmitInfo* s,VkFence f) {
  bv_test_submit_calls++;return bv_test_submit_result;
}
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_wait(VkDevice d,uint32_t n,const VkFence* f,VkBool32 all,uint64_t timeout) {
  bv_test_wait_calls++;bv_test_timeout=timeout;return bv_test_wait_result;
}
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_idle_error(VkDevice d) { return bv_test_idle_result; }
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_reset_error(VkCommandBuffer c,VkCommandBufferResetFlags f) { return VK_ERROR_OUT_OF_HOST_MEMORY; }
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_begin_error(VkCommandBuffer c,const VkCommandBufferBeginInfo* i) { return VK_ERROR_OUT_OF_HOST_MEMORY; }
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_end_error(VkCommandBuffer c) { return VK_ERROR_OUT_OF_HOST_MEMORY; }
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_status_success(VkDevice d,VkFence f) { return VK_SUCCESS; }
static Term bv_test_value(Env e,Term result) {
  assert(term_aux(result)==CID(Done));Term fields[1];bv_unpack(e,result,1,fields);return fields[0];
}
static void bv_test_status(Env e,Term result,uint32_t expected) { assert((uint32_t)bv_test_value(e,result)==expected); }
static Term bv_test_handle(BvRow* row) { return term_pak(CID(Device),row->id); }
static void bv_test_one(Env e,Term (*effect)(Env,Term*,IoWork*),BvRow* row,uint32_t expected) {
  Term args[]={bv_test_handle(row)};bv_test_result(e,effect(e,args,NULL),expected);
}
static void bv_test_record(Env e,BvRow* command,BvRow* src,BvRow* dst) {
  bv_test_one(e,bv_begin_command_buffer,command,0);
  Term copy[]={bv_test_handle(command),bv_test_handle(src),bv_test_handle(dst),bv_test_regions(e,0,0,1)};
  bv_test_result(e,bv_cmd_copy_buffer(e,copy,NULL),0);bv_test_one(e,bv_end_command_buffer,command,0);
}
static BvRow* bv_test_fence(Env e,BvRow* owner) {
  Term args[]={bv_test_handle(owner),term_pak(CID(False),0)};
  return bv_get(bv_key(e,bv_test_value(e,bv_create_fence(e,args,NULL))),BV_FENCE);
}
static BvRow* bv_test_pool(Env e,BvRow* owner) {
  Term args[]={bv_test_handle(owner)};
  return bv_get(bv_key(e,bv_test_value(e,bv_create_command_pool(e,args,NULL))),BV_POOL);
}
static BvRow* bv_test_command(Env e,BvRow* owner,BvRow* pool) {
  Term args[]={bv_test_handle(owner),bv_test_handle(pool)};
  return bv_get(bv_key(e,bv_test_value(e,bv_allocate_command_buffer(e,args,NULL))),BV_COMMAND);
}
static void bv_test_submit_call(Env e,BvRow* owner,BvRow* command,BvRow* fence,uint32_t expected) {
  Term args[]={bv_test_handle(owner),bv_test_handle(command),bv_test_handle(fence)};
  bv_test_result(e,bv_submit(e,args,NULL),expected);
}
static void bv_test_private(Env e,BvRow* owner,BvRow* command) {
  BvDevice* device=owner->context;
  bv_test_one(e,bv_reset_command_buffer,command,0);bv_test_one(e,bv_begin_command_buffer,command,0);bv_test_one(e,bv_end_command_buffer,command,0);
  Term args[]={bv_test_handle(owner),bv_test_handle(command)};bv_test_result(e,bv_submit_and_wait(e,args,NULL),0);
  BvRow* fence=device->convenience;assert(fence && !bv_active(owner,fence));
  bv_test_one(e,bv_fence_reset,fence,BV_INVALID);bv_test_one(e,bv_fence_status,fence,BV_INVALID);
  Term wait[]={bv_test_handle(fence),bv_words(e,0)};bv_test_result(e,bv_fence_wait(e,wait,NULL),BV_INVALID);
  Term destroy[]={bv_test_handle(owner),bv_test_handle(fence)};bv_test_result(e,bv_destroy_fence(e,destroy,NULL),BV_INVALID);
  bv_test_submit_call(e,owner,command,fence,BV_INVALID);assert(device->convenience==fence);
  bv_test_one(e,bv_reset_command_buffer,command,0);bv_test_one(e,bv_begin_command_buffer,command,0);bv_test_one(e,bv_end_command_buffer,command,0);
  PFN_vkQueueSubmit submit=device->QueueSubmit;PFN_vkWaitForFences waitfn=device->WaitForFences;
  device->QueueSubmit=bv_test_submit;device->WaitForFences=bv_test_wait;bv_test_submit_result=VK_ERROR_UNKNOWN;
  unsigned before=bv_test_wait_calls;
  Term retry[]={bv_test_handle(owner),bv_test_handle(command)};bv_test_result(e,bv_submit_and_wait(e,retry,NULL),(uint32_t)VK_ERROR_UNKNOWN);
  assert(bv_test_wait_calls==before && bv_command_fence(command)==fence);
  bv_test_one(e,bv_device_wait_idle,owner,0);assert(command->command.phase==BV_COMMAND_INVALID && device->convenience==fence);
  device->QueueSubmit=submit;device->WaitForFences=waitfn;
}
static void bv_test_loss(Env e,BvRow* owner) {
  BvDevice* original=owner->context;BvRow* instance=owner->parent;BvRow* physical=NULL;
  for (BvRow* r=bv_rows;r;r=r->next)
    if (r->kind==BV_PHYSICAL && r->parent==instance && r->handle==(uint64_t)(uintptr_t)original->physical) {physical=r;break;}
  assert(physical);
  for (unsigned path=0;path<3;path++) {
    Term fields[]={original->family,term_pak(CID(Nil),0)};
    Term create[]={bv_test_handle(instance),bv_test_handle(physical),bv_node(e,CID(DeviceCreateInfo),2,fields)};
    BvRow* lost=bv_get(bv_key(e,bv_test_value(e,bv_create_device(e,create,NULL))),BV_DEVICE);assert(lost);
    BvDevice* device=lost->context;BvRow* pool=bv_test_pool(e,lost);BvRow* command=bv_test_command(e,lost,pool);BvRow* fence=bv_test_fence(e,lost);
    bv_test_one(e,bv_begin_command_buffer,command,0);bv_test_one(e,bv_end_command_buffer,command,0);
    if (path==0) {
      device->QueueSubmit=bv_test_submit;bv_test_submit_result=VK_ERROR_DEVICE_LOST;
      bv_test_submit_call(e,lost,command,fence,(uint32_t)VK_ERROR_DEVICE_LOST);
    } else if (path==1) {
      bv_test_submit_call(e,lost,command,fence,0);
      assert(device->DeviceWaitIdle(device->handle)==VK_SUCCESS);
      device->WaitForFences=bv_test_wait;bv_test_wait_result=VK_ERROR_DEVICE_LOST;
      Term wait[]={bv_test_handle(fence),bv_words(e,UINT64_MAX)};bv_test_result(e,bv_fence_wait(e,wait,NULL),(uint32_t)VK_ERROR_DEVICE_LOST);
    } else {
      device->DeviceWaitIdle=bv_test_idle_error;bv_test_idle_result=VK_ERROR_DEVICE_LOST;
      bv_test_one(e,bv_device_wait_idle,lost,(uint32_t)VK_ERROR_DEVICE_LOST);
    }
    assert(device->health==BV_LOST && command->command.phase==BV_COMMAND_INVALID && !bv_active(lost,NULL));
    bv_test_one(e,bv_device_wait_idle,lost,(uint32_t)VK_ERROR_DEVICE_LOST);
    bv_test_one(e,bv_begin_command_buffer,command,(uint32_t)VK_ERROR_DEVICE_LOST);
    bv_test_one(e,bv_reset_command_buffer,command,(uint32_t)VK_ERROR_DEVICE_LOST);
    bv_test_one(e,bv_fence_status,fence,(uint32_t)VK_ERROR_DEVICE_LOST);
    bv_test_one(e,bv_fence_reset,fence,(uint32_t)VK_ERROR_DEVICE_LOST);
    Term destroy_pool[]={bv_test_handle(lost),bv_test_handle(pool)};bv_test_result(e,bv_destroy_command_pool(e,destroy_pool,NULL),0);
    Term destroy_fence[]={bv_test_handle(lost),bv_test_handle(fence)};bv_test_result(e,bv_destroy_fence(e,destroy_fence,NULL),0);
    bv_test_one(e,bv_destroy_device_effect,lost,(uint32_t)VK_ERROR_DEVICE_LOST);
  }
}
static void bv_test_loss_scope(Env e) {
  unsigned scope_allocations=bv_test_live_allocations,scope_rows=0;for(BvRow* row=bv_rows;row;row=row->next)scope_rows++;
  for(unsigned loss=0;loss<2;loss++) {
  BvRow* entry=bv_get(bv_key(e,bv_test_value(e,bv_entry_load(e,NULL,NULL))),BV_ENTRY);
  Term info[]={io_str(e,"injected loss cleanup",21),VK_API_VERSION_1_0,term_pak(CID(Nil),0),term_pak(CID(Nil),0)};
  Term create[]={bv_test_handle(entry),bv_node(e,CID(InstanceCreateInfo),4,info)};
  BvRow* instance=bv_get(bv_key(e,bv_test_value(e,bv_create_instance(e,create,NULL))),BV_INSTANCE);
  Term enumerate[]={bv_test_handle(instance)};Term list=bv_test_value(e,bv_enumerate_physical_devices(e,enumerate,NULL));
  assert(term_aux(list)==CID(Con));Term first[2];bv_unpack(e,list,2,first);
  BvRow* physical=bv_get(bv_key(e,first[0]),BV_PHYSICAL);term_sink(e,first[1]);
  BvInstance* dispatch=instance->context;uint32_t count=0;
  dispatch->queues((VkPhysicalDevice)(uintptr_t)physical->handle,&count,NULL);
  VkQueueFamilyProperties* queues=calloc(count,sizeof(*queues));assert(queues);
  dispatch->queues((VkPhysicalDevice)(uintptr_t)physical->handle,&count,queues);
  uint32_t family=0;while (family<count && !(queues[family].queueFlags & VK_QUEUE_GRAPHICS_BIT)) family++;
  free(queues);assert(family<count);
  Term fields[]={family,term_pak(CID(Nil),0)};
  Term device_args[]={bv_test_handle(instance),bv_test_handle(physical),bv_node(e,CID(DeviceCreateInfo),2,fields)};
  BvRow* device=bv_get(bv_key(e,bv_test_value(e,bv_create_device(e,device_args,NULL))),BV_DEVICE);
  BvRow* pool=bv_test_pool(e,device);BvRow* command=bv_test_command(e,device,pool);bv_test_fence(e,device);
  probe_add_cleanup_graph(e,device,command);
  descriptor_add_cleanup_graph(e,device,command);
  unsigned rows=0,allocations=bv_test_live_allocations;for(BvRow* r=bv_rows;r;r=r->next)rows++;
  uint32_t key=entry->id;PFN_vkDeviceWaitIdle actual_idle=((BvDevice*)device->context)->DeviceWaitIdle;
  ((BvDevice*)device->context)->DeviceWaitIdle=bv_test_idle_error;
  bv_test_idle_result=VK_ERROR_OUT_OF_HOST_MEMORY;
  bv_test_one(e,bv_entry_close,entry,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
  unsigned retained=0;for(BvRow* r=bv_rows;r;r=r->next)retained++;
  assert(retained==rows && bv_test_live_allocations==allocations && bv_get(key,BV_ENTRY)==entry && command->deps);
  bv_test_idle_result=VK_ERROR_DEVICE_LOST;
  if(!loss)((BvDevice*)device->context)->DeviceWaitIdle=actual_idle;
  bv_test_one(e,bv_entry_close,entry,loss ? (uint32_t)VK_ERROR_DEVICE_LOST : 0);assert(!bv_get(key,BV_ENTRY));
  unsigned after_rows=0;for(BvRow* row=bv_rows;row;row=row->next)after_rows++;
  assert(after_rows==scope_rows && bv_test_live_allocations==scope_allocations);
  }
  puts("Controlled image graph idle-error retry and known-loss ordered teardown passed");
  puts("Descriptor graph idle-error retry and loss cleanup returned exact row and metadata counts");
}
static void bv_test_unit3(Env e,BvRow* recording,BvRow* src,BvRow* dst) {
  BvRow* owner=bv_command_device(recording);BvDevice* device=owner->context;
  BvRow* pool=bv_test_pool(e,owner);BvRow* command=bv_test_command(e,owner,pool);BvRow* fence=bv_test_fence(e,owner);
  bv_test_record(e,command,src,dst);BvDep* refs=command->deps;assert(refs && refs->next && !refs->next->next);
  PFN_vkQueueSubmit submit=device->QueueSubmit;PFN_vkWaitForFences wait=device->WaitForFences;PFN_vkDeviceWaitIdle idle=device->DeviceWaitIdle;
  PFN_vkResetCommandBuffer reset=device->ResetCommandBuffer;
  device->QueueSubmit=bv_test_submit;device->WaitForFences=bv_test_wait;
  VkResult oom[]={VK_ERROR_OUT_OF_HOST_MEMORY,VK_ERROR_OUT_OF_DEVICE_MEMORY};
  for (unsigned j=0;j<2;j++) {
    bv_test_submit_result=oom[j];bv_test_submit_call(e,owner,command,fence,(uint32_t)oom[j]);
    assert(command->command.phase==BV_EXECUTABLE && !bv_active(owner,NULL) && command->deps==refs && !bv_test_wait_calls);
  }
  bv_test_submit_result=VK_ERROR_UNKNOWN;bv_test_submit_call(e,owner,command,fence,(uint32_t)VK_ERROR_UNKNOWN);
  assert(command->command.phase==BV_UNCERTAIN && bv_memory_busy(bv_bound_memory(src)));
  Term waitargs[]={bv_test_handle(fence),bv_words(e,0)};bv_test_result(e,bv_fence_wait(e,waitargs,NULL),BV_LIFETIME);
  bv_test_one(e,bv_fence_status,fence,BV_LIFETIME);assert(!bv_test_wait_calls);
  device->DeviceWaitIdle=bv_test_idle_error;bv_test_idle_result=VK_ERROR_OUT_OF_HOST_MEMORY;
  bv_test_one(e,bv_device_wait_idle,owner,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
  BvRow* entry=owner->parent->parent;bv_test_one(e,bv_entry_close,entry,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
  assert(bv_get(entry->id,BV_ENTRY)==entry && bv_active(owner,fence)==command && command->deps==refs);
  device->DeviceWaitIdle=idle;bv_test_one(e,bv_device_wait_idle,owner,0);
  assert(command->command.phase==BV_COMMAND_INVALID && !bv_memory_busy(bv_bound_memory(src)) && command->deps==refs);
  device->ResetCommandBuffer=bv_test_reset_error;bv_test_one(e,bv_reset_command_buffer,command,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
  assert(command->command.phase==BV_COMMAND_INVALID && command->deps==refs && bv_referenced(src));
  device->ResetCommandBuffer=reset;bv_test_one(e,bv_reset_command_buffer,command,0);assert(!command->deps);
  PFN_vkBeginCommandBuffer begin=device->BeginCommandBuffer;device->BeginCommandBuffer=bv_test_begin_error;
  bv_test_one(e,bv_begin_command_buffer,command,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);assert(command->command.phase==BV_COMMAND_INVALID);
  device->BeginCommandBuffer=begin;bv_test_one(e,bv_reset_command_buffer,command,0);
  bv_test_one(e,bv_begin_command_buffer,command,0);
  Term copy[]={bv_test_handle(command),bv_test_handle(src),bv_test_handle(dst),bv_test_regions(e,0,0,1)};bv_test_result(e,bv_cmd_copy_buffer(e,copy,NULL),0);
  PFN_vkEndCommandBuffer end=device->EndCommandBuffer;device->EndCommandBuffer=bv_test_end_error;
  bv_test_one(e,bv_end_command_buffer,command,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);assert(command->deps);
  device->EndCommandBuffer=end;bv_test_one(e,bv_reset_command_buffer,command,0);
  bv_test_record(e,command,src,dst);refs=command->deps;
  bv_test_submit_result=VK_SUCCESS;bv_test_submit_call(e,owner,command,fence,0);bv_test_wait_result=VK_TIMEOUT;
  uint64_t timeouts[]={0,UINT64_C(1)<<32,UINT64_MAX};
  for (unsigned j=0;j<3;j++) {
    Term args[]={bv_test_handle(fence),bv_words(e,timeouts[j])};bv_test_status(e,bv_fence_wait(e,args,NULL),VK_TIMEOUT);
    assert(bv_test_timeout==timeouts[j] && command->command.phase==BV_PENDING && bv_memory_busy(bv_bound_memory(src)));
  }
  bv_test_wait_result=VK_ERROR_OUT_OF_HOST_MEMORY;
  Term badwait[]={bv_test_handle(fence),bv_words(e,5)};bv_test_result(e,bv_fence_wait(e,badwait,NULL),(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
  assert(command->deps==refs && bv_active(owner,fence)==command);
  bv_test_wait_result=VK_SUCCESS;
  Term goodwait[]={bv_test_handle(fence),bv_words(e,5)};bv_test_status(e,bv_fence_wait(e,goodwait,NULL),VK_SUCCESS);
  assert(command->command.phase==BV_COMPLETED && command->deps==refs && !bv_memory_busy(bv_bound_memory(src)));
  bv_test_one(e,bv_reset_command_buffer,command,0);bv_test_record(e,command,src,dst);bv_test_submit_call(e,owner,command,fence,0);
  PFN_vkGetFenceStatus status=device->GetFenceStatus;device->GetFenceStatus=bv_test_status_success;
  bv_test_status(e,bv_fence_status(e,(Term[]){bv_test_handle(fence)},NULL),0);assert(command->command.phase==BV_COMPLETED);
  device->GetFenceStatus=status;device->QueueSubmit=submit;device->WaitForFences=wait;
  bv_test_private(e,owner,command);
  bv_test_one(e,bv_reset_command_buffer,command,0);
  Term destroy_pool[]={bv_test_handle(owner),bv_test_handle(pool)};bv_test_result(e,bv_destroy_command_pool(e,destroy_pool,NULL),0);
  Term destroy_fence[]={bv_test_handle(owner),bv_test_handle(fence)};bv_test_result(e,bv_destroy_fence(e,destroy_fence,NULL),0);
  bv_test_loss(e,owner);bv_test_loss_scope(e);
  puts("Injected submit OOM/uncertainty, wait/idle/reset/record errors, private fence isolation, timeout limbs, and sticky device loss passed");
}
