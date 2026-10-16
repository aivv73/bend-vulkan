static VkResult test_sync_result;
static unsigned test_sync_calls;
static VKAPI_ATTR VkResult VKAPI_CALL test_sync_submit(VkQueue queue,uint32_t count,const VkSubmitInfo* info,VkFence fence) {
  test_sync_calls++;assert(count==1 && info->commandBufferCount==1 && info->signalSemaphoreCount==1);
  return test_sync_result;
}
static Term test_sync_args(Env e,BvRow* owner,BvRow* command,BvRow* fence,BvRow* semaphore) {
  Term args[]={term_pak(CID(Device),owner->id),term_pak(CID(CommandBuffer),command->id),term_pak(CID(Fence),fence->id),term_pak(CID(Nil),0),io_node(e,CID(Con),term_pak(CID(Semaphore),semaphore->id),term_pak(CID(Nil),0))};
  return bv_submit_synced(e,args,NULL);
}
static Term test_submit_synced(Env e,Term* f,IoWork* w) {
  static bool checked;
  BvRow* owner=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_DEVICE);
  BvRow* command=bv_get(bv_key(e,term_keep(e,f[1],1)),BV_COMMAND);
  BvRow* fence=bv_public_fence(bv_key(e,term_keep(e,f[2],1)));
  if(!checked && owner && command && fence && term_aux(f[3])==CID(Nil) && term_aux(f[4])==CID(Con)) {
    Term list[2];Term signal=term_keep(e,f[4],1);bv_unpack(e,signal,2,list);term_sink(e,list[1]);BvRow* semaphore=bv_get(bv_key(e,list[0]),BV_SEMAPHORE);
    if(semaphore && semaphore->semaphore.phase==BV_SEM_UNUSED) {
      checked=true;BvDevice* device=owner->context;PFN_vkQueueSubmit saved=device->QueueSubmit;device->QueueSubmit=test_sync_submit;
      BvCommand before=command->command;BvDep* refs=command->deps;unsigned allocations=bv_test_live_allocations;
      bv_test_alloc_at=0;bv_test_alloc_fail=1;test_sync_calls=0;
      bv_test_result(e,test_sync_args(e,owner,command,fence,semaphore),BV_LIMIT);
      assert(!test_sync_calls && command->deps==refs && semaphore->semaphore.phase==BV_SEM_UNUSED);bv_test_alloc_fail=0;
      test_sync_result=VK_ERROR_OUT_OF_HOST_MEMORY;
      bv_test_result(e,test_sync_args(e,owner,command,fence,semaphore),(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
      assert(test_sync_calls==1 && command->command.phase==BV_EXECUTABLE && semaphore->semaphore.phase==BV_SEM_UNUSED && command->deps==refs);
      test_sync_result=VK_ERROR_UNKNOWN;
      bv_test_result(e,test_sync_args(e,owner,command,fence,semaphore),(uint32_t)VK_ERROR_UNKNOWN);
      assert(command->command.phase==BV_UNCERTAIN && semaphore->semaphore.phase==BV_SEM_UNCERTAIN && bv_referenced(semaphore));
      bv_test_result(e,bv_fence_observe(e,fence,0,0),BV_LIFETIME);
      Term destroy[]={term_pak(CID(Device),owner->id),term_pak(CID(Semaphore),semaphore->id)};
      bv_test_result(e,bv_destroy_semaphore(e,destroy,NULL),BV_LIFETIME);
      Term reset[]={term_pak(CID(CommandBuffer),command->id)};bv_test_result(e,bv_reset_command_buffer(e,reset,NULL),BV_LIFETIME);
      assert(bv_idle(owner)==VK_SUCCESS && command->command.phase==BV_COMMAND_INVALID && semaphore->semaphore.phase==BV_SEM_QUARANTINED);
      assert(command->deps==refs && bv_test_live_allocations==allocations);
      command->command=before;semaphore->semaphore=(BvSemaphore){0};
      test_sync_result=VK_SUCCESS;bv_test_result(e,test_sync_args(e,owner,command,fence,semaphore),0);
      assert(command->command.phase==BV_PENDING && semaphore->semaphore.phase==BV_SEM_SIGNAL_PENDING);
      BvRow* fresh=bv_add(BV_SEMAPHORE,owner);assert(fresh);BvDep* pending=command->deps;
      bv_test_result(e,test_sync_args(e,owner,command,fence,fresh),BV_LIFETIME);
      assert(fresh->semaphore.phase==BV_SEM_UNUSED && command->deps==pending);bv_remove(fresh);
      bv_complete(command);assert(semaphore->semaphore.phase==BV_SEM_SIGNALED && command->deps==refs);
      command->command=before;semaphore->semaphore=(BvSemaphore){0};device->QueueSubmit=saved;
      assert(bv_test_live_allocations==allocations);
      puts("Controlled semaphore allocation rollback, OOM, uncertainty and signal retention passed");
    }
  }
  return bv_submit_synced(e,f,w);
}
