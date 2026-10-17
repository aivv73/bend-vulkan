static VKAPI_ATTR VkResult VKAPI_CALL test_query_create_oom(VkDevice d,const VkQueryPoolCreateInfo* i,const VkAllocationCallbacks* a,VkQueryPool* out) {return VK_ERROR_OUT_OF_DEVICE_MEMORY;}
static VKAPI_ATTR VkResult VKAPI_CALL test_query_results_oom(VkDevice d,VkQueryPool p,uint32_t first,uint32_t count,size_t size,void* data,VkDeviceSize stride,VkQueryResultFlags flags) {return VK_ERROR_OUT_OF_HOST_MEMORY;}
static Term test_query_duration_call(Env e,BvRow* owner,uint64_t start,uint64_t end,uint64_t bound) {
  Term args[]={bv_test_handle(owner),bv_words(e,start),bv_words(e,end),bv_words(e,bound)};return bv_timestamp_duration(e,args,NULL);
}
static Term test_query_results(Env e,Term* f,IoWork* w) {
  static bool checked;
  BvRow* owner=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_DEVICE),*pool=bv_get(bv_key(e,term_keep(e,f[1],1)),BV_QUERY_POOL);
  if (!checked && owner && pool && pool->object.queries.slots[0].ready) {
    checked=true;BvDevice* device=owner->context;unsigned baseline=bv_test_live_allocations;
    for (unsigned fail=1;fail<=3;fail++) {
      bv_test_alloc_at=0;bv_test_alloc_fail=fail;
      Term args[]={bv_test_handle(owner),2};Term result=bv_create_timestamp_pool(e,args,NULL);bv_test_alloc_fail=0;
      if (term_aux(result)==CID(Done)) {
        BvRow* created=bv_get(bv_key(e,bv_test_value(e,result)),BV_QUERY_POOL);assert(created);
        Term drop[]={bv_test_handle(owner),term_pak(CID(QueryPool),created->id)};bv_test_result(e,bv_destroy_query_pool(e,drop,NULL),0);
      } else bv_test_result(e,result,BV_LIMIT);
      assert(bv_test_live_allocations==baseline);
    }
    PFN_vkCreateQueryPool create=device->CreateQueryPool;device->CreateQueryPool=test_query_create_oom;
    Term create_args[]={bv_test_handle(owner),2};bv_test_result(e,bv_create_timestamp_pool(e,create_args,NULL),(uint32_t)VK_ERROR_OUT_OF_DEVICE_MEMORY);device->CreateQueryPool=create;
    assert(bv_test_live_allocations==baseline);
    unsigned bits=device->queue_properties.timestampValidBits;float period=device->limits.timestampPeriod;
    device->queue_properties.timestampValidBits=8;device->limits.timestampPeriod=2.0f;
    assert((uint32_t)bv_test_value(e,test_query_duration_call(e,owner,250,2,16))==UINT32_C(0x41800000));
    bv_test_result(e,test_query_duration_call(e,owner,250,2,15),BV_ARGUMENT);
    bv_test_result(e,test_query_duration_call(e,owner,250,2,256),BV_ARGUMENT);
    device->queue_properties.timestampValidBits=64;device->limits.timestampPeriod=1.0f;
    assert((uint32_t)bv_test_value(e,test_query_duration_call(e,owner,UINT64_MAX-3,4,16))==UINT32_C(0x41000000));
    device->queue_properties.timestampValidBits=0;bv_test_result(e,test_query_duration_call(e,owner,0,1,16),BV_ARGUMENT);
    device->queue_properties.timestampValidBits=bits;device->limits.timestampPeriod=period;
    BvRow* command=bv_get(pool->object.queries.slots[0].command,BV_COMMAND);assert(command && command->command.phase==BV_COMPLETED);
    BvDep* refs=command->deps;PFN_vkResetCommandBuffer reset=device->ResetCommandBuffer;device->ResetCommandBuffer=bv_test_reset_error;
    bv_test_one(e,bv_reset_command_buffer,command,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);assert(command->deps==refs && bv_referenced(pool));
    Term drop[]={bv_test_handle(owner),term_pak(CID(QueryPool),pool->id)};bv_test_result(e,bv_destroy_query_pool(e,drop,NULL),BV_LIFETIME);device->ResetCommandBuffer=reset;
    PFN_vkGetQueryPoolResults results=device->GetQueryPoolResults;device->GetQueryPoolResults=test_query_results_oom;
    Term query[]={bv_test_handle(owner),term_pak(CID(QueryPool),pool->id),0,2};bv_test_result(e,bv_timestamp_results(e,query,NULL),(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);device->GetQueryPoolResults=results;
    assert(bv_test_live_allocations==baseline);
    puts("Timestamp allocation/dispatch OOM, finite wrap bounds, failed-reset references and result retry passed");
  }
  return bv_timestamp_results(e,f,w);
}
