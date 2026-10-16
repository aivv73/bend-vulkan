static unsigned descriptor_layout_calls,descriptor_pool_calls,descriptor_allocate_calls,descriptor_update_calls,descriptor_bind_calls,descriptor_free_calls,descriptor_reset_calls,descriptor_sampler_calls,descriptor_destroy_calls;
static unsigned descriptor_pipeline_layout_calls;
static VkResult descriptor_native_result;
static bool descriptor_fail_update;
static VKAPI_ATTR VkResult VKAPI_CALL descriptor_layout_create(VkDevice d,const VkDescriptorSetLayoutCreateInfo* p,const VkAllocationCallbacks* a,VkDescriptorSetLayout* out) {
  descriptor_layout_calls++;assert(!a && !p->flags && *out==VK_NULL_HANDLE);*out=(VkDescriptorSetLayout)(uintptr_t)0xd1;return descriptor_native_result;
}
static VKAPI_ATTR void VKAPI_CALL descriptor_layout_destroy(VkDevice d,VkDescriptorSetLayout p,const VkAllocationCallbacks* a) {descriptor_destroy_calls++;}
static VKAPI_ATTR VkResult VKAPI_CALL descriptor_pool_create(VkDevice d,const VkDescriptorPoolCreateInfo* p,const VkAllocationCallbacks* a,VkDescriptorPool* out) {
  descriptor_pool_calls++;assert(p->flags==VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT && p->maxSets && *out==VK_NULL_HANDLE);*out=(VkDescriptorPool)(uintptr_t)0xd2;return descriptor_native_result;
}
static VKAPI_ATTR void VKAPI_CALL descriptor_pool_destroy(VkDevice d,VkDescriptorPool p,const VkAllocationCallbacks* a) {descriptor_destroy_calls++;}
static VKAPI_ATTR VkResult VKAPI_CALL descriptor_allocate(VkDevice d,const VkDescriptorSetAllocateInfo* p,VkDescriptorSet* out) {
  descriptor_allocate_calls++;assert(p->descriptorSetCount==1 && p->pSetLayouts && *out==VK_NULL_HANDLE);*out=(VkDescriptorSet)(uintptr_t)0xd3;return descriptor_native_result;
}
static VKAPI_ATTR VkResult VKAPI_CALL descriptor_free(VkDevice d,VkDescriptorPool p,uint32_t n,const VkDescriptorSet* s) {descriptor_free_calls++;assert(n==1);return descriptor_native_result;}
static VKAPI_ATTR VkResult VKAPI_CALL descriptor_reset(VkDevice d,VkDescriptorPool p,VkDescriptorPoolResetFlags flags) {descriptor_reset_calls++;assert(!flags);return descriptor_native_result;}
static VKAPI_ATTR VkResult VKAPI_CALL descriptor_sampler_create(VkDevice d,const VkSamplerCreateInfo* p,const VkAllocationCallbacks* a,VkSampler* out) {
  descriptor_sampler_calls++;assert(!p->anisotropyEnable && !p->compareEnable && !p->unnormalizedCoordinates && p->mipLodBias==0 && *out==VK_NULL_HANDLE);*out=(VkSampler)(uintptr_t)0xd4;return descriptor_native_result;
}
static VKAPI_ATTR void VKAPI_CALL descriptor_sampler_destroy(VkDevice d,VkSampler p,const VkAllocationCallbacks* a) {descriptor_destroy_calls++;}
static VKAPI_ATTR void VKAPI_CALL descriptor_update(VkDevice d,uint32_t n,const VkWriteDescriptorSet* writes,uint32_t copies,const VkCopyDescriptorSet* copy) {
  descriptor_update_calls++;assert(n && !copies && !copy);
  for(uint32_t j=0;j<n;j++) {
    assert(writes[j].descriptorCount==1 && writes[j].dstSet && writes[j].sType==VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET);
    if(writes[j].descriptorType==VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER)assert(writes[j].pBufferInfo && writes[j].pBufferInfo->range);
    else assert(writes[j].descriptorType==VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER && writes[j].pImageInfo && writes[j].pImageInfo->sampler && writes[j].pImageInfo->imageView);
  }
}
static VKAPI_ATTR void VKAPI_CALL descriptor_bind(VkCommandBuffer c,VkPipelineBindPoint point,VkPipelineLayout l,uint32_t first,uint32_t count,const VkDescriptorSet* sets,uint32_t dynamic,const uint32_t* offsets) {
  descriptor_bind_calls++;assert(point==VK_PIPELINE_BIND_POINT_GRAPHICS && count && !dynamic && !offsets);
}
static VKAPI_ATTR VkResult VKAPI_CALL descriptor_pipeline_layout_create(VkDevice d,const VkPipelineLayoutCreateInfo* p,const VkAllocationCallbacks* a,VkPipelineLayout* out) {
  descriptor_pipeline_layout_calls++;assert(p->setLayoutCount==1 && p->pSetLayouts && !p->pushConstantRangeCount && *out==VK_NULL_HANDLE);*out=(VkPipelineLayout)(uintptr_t)0xd5;return descriptor_native_result;
}
static VKAPI_ATTR void VKAPI_CALL descriptor_pipeline_layout_destroy(VkDevice d,VkPipelineLayout p,const VkAllocationCallbacks* a) {descriptor_destroy_calls++;}
static VKAPI_ATTR void VKAPI_CALL descriptor_pipeline_bind(VkCommandBuffer c,VkPipelineBindPoint b,VkPipeline p) {}
static VKAPI_ATTR void VKAPI_CALL descriptor_nearest_format(VkPhysicalDevice p,VkFormat f,VkFormatProperties* out) {
  *out=(VkFormatProperties){.optimalTilingFeatures=VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT};
}
static Term descriptor_list(Env e,Term value) {return io_node(e,CID(Con),value,term_pak(CID(Nil),0));}
static Term descriptor_schema_info(Env e,uint32_t kind,uint32_t count,uint32_t stages) {
  return bv_node(e,CID(DescriptorSetLayoutCreateInfo),1,(Term[]){descriptor_list(e,bv_node(e,CID(DescriptorBinding),4,(Term[]){kind ? 9 : 3,kind,count,stages}))});
}
static Term descriptor_pool_info(Env e,uint32_t sets,uint32_t uniforms,uint32_t sampled) {
  Term sizes=term_pak(CID(Nil),0);
  if(sampled)sizes=io_node(e,CID(Con),bv_node(e,CID(DescriptorPoolSize),2,(Term[]){1,sampled}),sizes);
  if(uniforms)sizes=io_node(e,CID(Con),bv_node(e,CID(DescriptorPoolSize),2,(Term[]){0,uniforms}),sizes);
  return bv_node(e,CID(DescriptorPoolCreateInfo),2,(Term[]){sets,sizes});
}
static Term descriptor_sampler_info(Env e,unsigned lane,uint32_t value) {
  Term p[]={0,0,0,2,2,2,0,f32_rewrap(1),4};if(lane<9)p[lane]=value;
  return bv_node(e,CID(SamplerCreateInfo),9,p);
}
static Term descriptor_uniform_write(Env e,BvRow* a,BvRow* b,uint32_t binding,uint32_t first,uint64_t offset,uint64_t range) {
  Term values=term_pak(CID(Nil),0);
  if(b)values=descriptor_list(e,bv_node(e,CID(DescriptorBuffer),5,(Term[]){b->id,0,0,16,0}));
  values=io_node(e,CID(Con),bv_node(e,CID(DescriptorBuffer),5,(Term[]){a->id,(uint32_t)offset,offset>>32,(uint32_t)range,range>>32}),values);
  return descriptor_list(e,bv_node(e,CID(UniformWrite),3,(Term[]){binding,first,values}));
}
static Term descriptor_sample_write(Env e,BvRow* view,BvRow* sampler,uint32_t layout) {
  return descriptor_list(e,bv_node(e,CID(SampledWrite),3,(Term[]){9,0,descriptor_list(e,bv_node(e,CID(DescriptorImage),3,(Term[]){view->id,sampler->id,layout}))}));
}
static Term descriptor_two(Env e,Term (*effect)(Env,Term*,IoWork*),BvRow* owner,BvRow* row) {return effect(e,(Term[]){bv_test_handle(owner),bv_test_handle(row)},NULL);}
static BvRow* descriptor_set_new(Env e,BvRow* owner,BvRow* pool,BvRow* layout) {
  return bv_get(bv_key(e,bv_test_value(e,bv_allocate_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(pool),bv_test_handle(layout)},NULL))),BV_DESCRIPTOR_SET);
}
static void descriptor_update_uniform(Env e,BvRow* owner,BvRow* set,BvRow* a,BvRow* b,uint32_t binding,uint32_t first,uint64_t offset,uint64_t range,uint32_t expected) {
  bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(set),descriptor_uniform_write(e,a,b,binding,first,offset,range)},NULL),expected);
}
static Term descriptor_bind_call(Env e,BvRow* command,BvRow* set,uint32_t first) {
  return bv_cmd_bind_descriptor_sets(e,(Term[]){bv_test_handle(command),first,descriptor_list(e,bv_test_handle(set))},NULL);
}
static void descriptor_add_cleanup_graph(Env e,BvRow* owner,BvRow* command) {
  BvDevice* d=owner->context;BvRow* view=NULL;
  for(BvRow* row=bv_rows;row;row=row->next)if(row->parent==owner && row->kind==BV_IMAGE_VIEW)view=row;
  assert(view);
  BvRow* buffer=bv_get(bv_key(e,bv_test_value(e,bv_create_buffer(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(BufferCreateInfo),3,(Term[]){16,0,16})},NULL))),BV_BUFFER);
  uint32_t type=0;while(!(buffer->requirements.memoryTypeBits&(1u<<type)))type++;
  BvRow* memory=bv_get(bv_key(e,bv_test_value(e,bv_allocate_memory(e,(Term[]){bv_test_handle(owner),bv_words(e,buffer->requirements.size),type},NULL))),BV_MEMORY);
  bv_test_result(e,bv_bind_buffer_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(buffer),bv_test_handle(memory),bv_words(e,0)},NULL),0);
  BvRow* schema=bv_get(bv_key(e,bv_test_value(e,bv_create_descriptor_set_layout(e,(Term[]){bv_test_handle(owner),descriptor_schema_info(e,0,2,17)},NULL))),BV_DESCRIPTOR_LAYOUT);
  BvRow* sampled_schema=bv_get(bv_key(e,bv_test_value(e,bv_create_descriptor_set_layout(e,(Term[]){bv_test_handle(owner),descriptor_schema_info(e,1,1,16)},NULL))),BV_DESCRIPTOR_LAYOUT);
  BvRow* pool=bv_get(bv_key(e,bv_test_value(e,bv_create_descriptor_pool(e,(Term[]){bv_test_handle(owner),descriptor_pool_info(e,2,2,1)},NULL))),BV_DESCRIPTOR_POOL);
  BvRow* sampler=bv_get(bv_key(e,bv_test_value(e,bv_create_sampler(e,(Term[]){bv_test_handle(owner),descriptor_sampler_info(e,9,0)},NULL))),BV_SAMPLER);
  BvRow* uniform=descriptor_set_new(e,owner,pool,schema),*sampled=descriptor_set_new(e,owner,pool,sampled_schema);
  descriptor_update_uniform(e,owner,uniform,buffer,buffer,3,0,0,16,0);
  bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(sampled),descriptor_sample_write(e,view,sampler,5)},NULL),0);
  Term layouts=io_node(e,CID(Con),bv_test_handle(schema),descriptor_list(e,bv_test_handle(sampled_schema)));
  BvRow* layout=bv_get(bv_key(e,bv_test_value(e,bv_create_pipeline_layout(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(PipelineLayoutCreateInfo),4,(Term[]){layouts,0,0,0})},NULL))),BV_LAYOUT);
  BvRow* resources[]={uniform,sampled,layout};assert(bv_prepare_refs(command,3,resources));
  assert(bv_may_reach_depth(command,memory,BV_KIND_COUNT) && bv_referenced(sampler));
}
static void descriptor_probes(Env e,BvRow* owner) {
  BvDevice* d=owner->context;BvDevice saved=*d;unsigned allocations=bv_test_live_allocations;
  BvRow *a=NULL,*b=NULL,*image=NULL,*unrelated=NULL;
  for(BvRow* row=bv_rows;row;row=row->next)if(row->parent==owner) {
    if(row->kind==BV_BUFFER && (row->flags&VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT)) {if(!a)a=row;else b=row;}
    if(row->kind==BV_BUFFER && row->size==128 && (row->flags&VK_BUFFER_USAGE_TRANSFER_DST_BIT))unrelated=bv_bound_memory(row);
    if(row->kind==BV_IMAGE && row->object.image.format==VK_FORMAT_D32_SFLOAT && (row->object.image.usage&VK_IMAGE_USAGE_SAMPLED_BIT))image=row;
  }
  assert(a && b && image && unrelated && bv_bound_memory(a)!=unrelated && bv_bound_memory(b)!=unrelated);
  BvRow leaf={0},root={0};BvDep deep={.target=&leaf};root.deps=&deep;
  assert(bv_may_reach_depth(&root,unrelated,0) && !bv_may_reach_depth(&leaf,unrelated,0));
  d->CreatePipelineLayout=descriptor_pipeline_layout_create;d->DestroyPipelineLayout=descriptor_pipeline_layout_destroy;
  d->CreateDescriptorSetLayout=descriptor_layout_create;d->DestroyDescriptorSetLayout=descriptor_layout_destroy;
  d->CreateDescriptorPool=descriptor_pool_create;d->DestroyDescriptorPool=descriptor_pool_destroy;d->AllocateDescriptorSets=descriptor_allocate;
  d->FreeDescriptorSets=descriptor_free;d->ResetDescriptorPool=descriptor_reset;d->UpdateDescriptorSets=descriptor_update;
  d->CreateSampler=descriptor_sampler_create;d->DestroySampler=descriptor_sampler_destroy;d->CmdBindDescriptorSets=descriptor_bind;d->CmdBindPipeline=descriptor_pipeline_bind;
  descriptor_native_result=VK_SUCCESS;
  for(unsigned fail=1;fail<=2;fail++) {
    bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    bv_test_result(e,bv_create_descriptor_set_layout(e,(Term[]){bv_test_handle(owner),descriptor_schema_info(e,0,2,17)},NULL),BV_LIMIT);
    assert(!descriptor_layout_calls && bv_test_live_allocations==allocations);
  }
  bv_test_alloc_at=0;bv_test_alloc_fail=1;
  bv_test_result(e,bv_create_descriptor_pool(e,(Term[]){bv_test_handle(owner),descriptor_pool_info(e,2,4,2)},NULL),BV_LIMIT);
  bv_test_alloc_at=0;
  bv_test_result(e,bv_create_sampler(e,(Term[]){bv_test_handle(owner),descriptor_sampler_info(e,9,0)},NULL),BV_LIMIT);
  bv_test_alloc_fail=0;assert(!descriptor_pool_calls && !descriptor_sampler_calls);
  uint32_t sampler_limit=d->limits.maxSamplerAllocationCount;d->limits.maxSamplerAllocationCount=0;
  bv_test_result(e,bv_create_sampler(e,(Term[]){bv_test_handle(owner),descriptor_sampler_info(e,9,0)},NULL),BV_LIMIT);
  d->limits.maxSamplerAllocationCount=sampler_limit;assert(!descriptor_sampler_calls);
  const uint32_t invalid_sampler[]={2,2,2,4,4,4,0xbf800000,0x7f800000,6};
  for(unsigned j=0;j<9;j++)bv_test_result(e,bv_create_sampler(e,(Term[]){bv_test_handle(owner),descriptor_sampler_info(e,j,invalid_sampler[j])},NULL),BV_ARGUMENT);
  bv_test_result(e,bv_create_sampler(e,(Term[]){bv_test_handle(owner),descriptor_sampler_info(e,6,f32_rewrap(2))},NULL),BV_ARGUMENT);
  assert(!descriptor_sampler_calls);
  for(unsigned j=0;j<4;j++)bv_test_result(e,bv_create_descriptor_set_layout(e,(Term[]){bv_test_handle(owner),descriptor_schema_info(e,j==0 ? 2 : 0,j==1 ? 0 : 2,j==2 ? 32 : j==3 ? 0 : 17)},NULL),BV_ARGUMENT);
  assert(!descriptor_layout_calls);
  uint32_t stage_limit=d->limits.maxPerStageDescriptorUniformBuffers;d->limits.maxPerStageDescriptorUniformBuffers=1;
  bv_test_result(e,bv_create_descriptor_set_layout(e,(Term[]){bv_test_handle(owner),descriptor_schema_info(e,0,2,17)},NULL),BV_LIMIT);
  d->limits.maxPerStageDescriptorUniformBuffers=stage_limit;
  uint32_t set_limit=d->limits.maxDescriptorSetUniformBuffers;d->limits.maxDescriptorSetUniformBuffers=1;
  bv_test_result(e,bv_create_descriptor_set_layout(e,(Term[]){bv_test_handle(owner),descriptor_schema_info(e,0,2,17)},NULL),BV_LIMIT);
  d->limits.maxDescriptorSetUniformBuffers=set_limit;assert(!descriptor_layout_calls);
  descriptor_native_result=VK_ERROR_OUT_OF_HOST_MEMORY;
  bv_test_result(e,bv_create_descriptor_set_layout(e,(Term[]){bv_test_handle(owner),descriptor_schema_info(e,0,2,17)},NULL),(uint32_t)descriptor_native_result);
  bv_test_result(e,bv_create_descriptor_pool(e,(Term[]){bv_test_handle(owner),descriptor_pool_info(e,2,4,2)},NULL),(uint32_t)descriptor_native_result);
  bv_test_result(e,bv_create_sampler(e,(Term[]){bv_test_handle(owner),descriptor_sampler_info(e,9,0)},NULL),(uint32_t)descriptor_native_result);
  assert(bv_test_live_allocations==allocations);descriptor_native_result=VK_SUCCESS;
  BvRow* schema=bv_get(bv_key(e,bv_test_value(e,bv_create_descriptor_set_layout(e,(Term[]){bv_test_handle(owner),descriptor_schema_info(e,0,2,17)},NULL))),BV_DESCRIPTOR_LAYOUT);
  BvRow* sampled_schema=bv_get(bv_key(e,bv_test_value(e,bv_create_descriptor_set_layout(e,(Term[]){bv_test_handle(owner),descriptor_schema_info(e,1,1,16)},NULL))),BV_DESCRIPTOR_LAYOUT);
  BvRow* pool=bv_get(bv_key(e,bv_test_value(e,bv_create_descriptor_pool(e,(Term[]){bv_test_handle(owner),descriptor_pool_info(e,6,4,1)},NULL))),BV_DESCRIPTOR_POOL);
  BvRow* sampler=bv_get(bv_key(e,bv_test_value(e,bv_create_sampler(e,(Term[]){bv_test_handle(owner),descriptor_sampler_info(e,9,0)},NULL))),BV_SAMPLER);
  unsigned sampler_calls=descriptor_sampler_calls;sampler_limit=d->limits.maxSamplerAllocationCount;d->limits.maxSamplerAllocationCount=1;
  bv_test_result(e,bv_create_sampler(e,(Term[]){bv_test_handle(owner),descriptor_sampler_info(e,9,0)},NULL),BV_LIMIT);assert(descriptor_sampler_calls==sampler_calls);d->limits.maxSamplerAllocationCount=sampler_limit;
  unsigned layout_allocations=bv_test_live_allocations;
  for(unsigned fail=1;fail<=3;fail++) {
    bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    bv_test_result(e,bv_create_pipeline_layout(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(PipelineLayoutCreateInfo),4,(Term[]){descriptor_list(e,bv_test_handle(schema)),0,0,0})},NULL),BV_LIMIT);
    assert(!descriptor_pipeline_layout_calls && bv_test_live_allocations==layout_allocations);
  }
  bv_test_alloc_fail=0;descriptor_native_result=VK_ERROR_OUT_OF_HOST_MEMORY;
  bv_test_result(e,bv_create_pipeline_layout(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(PipelineLayoutCreateInfo),4,(Term[]){descriptor_list(e,bv_test_handle(schema)),0,0,0})},NULL),(uint32_t)descriptor_native_result);
  assert(bv_test_live_allocations==layout_allocations);descriptor_native_result=VK_SUCCESS;
  BvRow* view=NULL;for(BvRow* row=bv_rows;row;row=row->next)if(row->kind==BV_IMAGE_VIEW && bv_dependency(row,BV_DEP_VIEW_IMAGE)->target==image)view=row;assert(view);
  unsigned before=bv_test_live_allocations,native=descriptor_allocate_calls;
  for(unsigned fail=1;fail<=4;fail++) {
    bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    bv_test_result(e,bv_allocate_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(pool),bv_test_handle(schema)},NULL),BV_LIMIT);
    assert(descriptor_allocate_calls==native && bv_test_live_allocations==before && !pool->object.descriptor_pool.sets);
  }
  bv_test_alloc_fail=0;descriptor_native_result=VK_ERROR_OUT_OF_DEVICE_MEMORY;
  bv_test_result(e,bv_allocate_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(pool),bv_test_handle(schema)},NULL),(uint32_t)descriptor_native_result);
  assert(!pool->object.descriptor_pool.sets && bv_test_live_allocations==before);descriptor_native_result=VK_SUCCESS;
  BvRow* set=descriptor_set_new(e,owner,pool,schema),*second=descriptor_set_new(e,owner,pool,schema),*sampled=descriptor_set_new(e,owner,pool,sampled_schema);
  bv_test_result(e,bv_allocate_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(pool),bv_test_handle(schema)},NULL),BV_LIMIT);
  bv_test_result(e,bv_allocate_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(pool),bv_test_handle(sampled_schema)},NULL),BV_LIMIT);
  descriptor_update_uniform(e,owner,set,a,b,3,0,0,16,0);descriptor_update_uniform(e,owner,second,a,b,3,0,0,16,0);
  bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(sampled),descriptor_sample_write(e,view,sampler,4)},NULL),0);
  before=bv_test_live_allocations;native=descriptor_update_calls;BvDescriptorSlot* old=set->object.set.slots;BvDep* old_deps=set->deps;
  for(unsigned fail=1;fail<=9;fail++) {
    bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    descriptor_update_uniform(e,owner,set,b,a,3,0,0,16,BV_LIMIT);
    assert(set->object.set.slots==old && set->deps==old_deps && old[0].data.uniform.buffer==a && old[1].data.uniform.buffer==b && bv_test_live_allocations==before && descriptor_update_calls==native);
  }
  bv_test_alloc_fail=0;
  BvDescriptorSlot* sampled_old=sampled->object.set.slots;BvDep* sampled_deps=sampled->deps;
  for(unsigned fail=1;fail<=9;fail++) {
    bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(sampled),descriptor_sample_write(e,view,sampler,5)},NULL),BV_LIMIT);
    assert(sampled->object.set.slots==sampled_old && sampled->deps==sampled_deps && sampled_old[0].data.sampled.layout==4 && bv_test_live_allocations==before && descriptor_update_calls==native);
  }
  bv_test_alloc_fail=0;
  const uint64_t offsets[]={1,UINT64_MAX,UINT64_C(1)<<32,0,0};const uint64_t ranges[]={16,16,16,0,UINT64_MAX};
  for(unsigned j=0;j<5;j++)descriptor_update_uniform(e,owner,set,a,NULL,3,0,offsets[j],ranges[j],BV_ARGUMENT);
  VkDeviceSize alignment=d->limits.minUniformBufferOffsetAlignment;d->limits.minUniformBufferOffsetAlignment=16;
  descriptor_update_uniform(e,owner,set,a,NULL,3,0,1,1,BV_ARGUMENT);d->limits.minUniformBufferOffsetAlignment=alignment;
  uint32_t uniform_range=d->limits.maxUniformBufferRange;d->limits.maxUniformBufferRange=8;
  descriptor_update_uniform(e,owner,set,a,NULL,3,0,0,16,BV_ARGUMENT);d->limits.maxUniformBufferRange=uniform_range;
  descriptor_update_uniform(e,owner,set,a,NULL,7,0,0,16,BV_ARGUMENT);descriptor_update_uniform(e,owner,set,a,NULL,3,2,0,16,BV_ARGUMENT);
  uint32_t usage=a->flags;a->flags=0;descriptor_update_uniform(e,owner,set,a,NULL,3,0,0,16,BV_ARGUMENT);a->flags=usage;
  BvDep* binding=a->deps;a->deps=NULL;descriptor_update_uniform(e,owner,set,a,NULL,3,0,0,16,BV_LIFETIME);a->deps=binding;
  BvRow* foreign=bv_add(BV_DEVICE,owner->parent);assert(foreign);
  bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(foreign),bv_test_handle(set),descriptor_uniform_write(e,a,b,3,0,0,16)},NULL),BV_INVALID);bv_remove(foreign);
  Term duplicate=descriptor_uniform_write(e,a,NULL,3,0,0,16),item[2];bv_unpack(e,duplicate,2,item);
  duplicate=io_node(e,CID(Con),item[0],descriptor_uniform_write(e,b,NULL,3,0,0,16));
  bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(set),duplicate},NULL),BV_ARGUMENT);
  bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(set),descriptor_sample_write(e,view,sampler,4)},NULL),BV_ARGUMENT);
  BvImage saved_image=image->object.image;image->object.image.usage=VK_IMAGE_USAGE_SAMPLED_BIT;
  bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(sampled),descriptor_sample_write(e,view,sampler,4)},NULL),BV_ARGUMENT);
  image->object.image=saved_image;image->object.image.storage=BV_BORROWED_IMAGE;
  bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(sampled),descriptor_sample_write(e,view,sampler,4)},NULL),BV_LIFETIME);image->object.image=saved_image;
  for(unsigned layout=0;layout<8;layout++)if(layout!=1 && layout!=4 && layout!=5)bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(sampled),descriptor_sample_write(e,view,sampler,layout)},NULL),BV_ARGUMENT);
  BvSampler saved_sampler=sampler->object.sampler;sampler->object.sampler.min=VK_FILTER_LINEAR;
  BvInstance* instance=owner->parent->context;VkFormatProperties props;instance->formats(d->physical,image->object.image.format,&props);
  if(!(props.optimalTilingFeatures&VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT))bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(sampled),descriptor_sample_write(e,view,sampler,4)},NULL),BV_ARGUMENT);
  PFN_vkGetPhysicalDeviceFormatProperties formats=instance->formats;instance->formats=descriptor_nearest_format;
  bv_test_result(e,bv_update_descriptor_set(e,(Term[]){bv_test_handle(owner),bv_test_handle(sampled),descriptor_sample_write(e,view,sampler,4)},NULL),BV_ARGUMENT);
  instance->formats=formats;
  sampler->object.sampler=saved_sampler;assert(descriptor_update_calls==native && set->object.set.slots==old && set->deps==old_deps && bv_test_live_allocations==before);
  bv_test_result(e,descriptor_two(e,bv_destroy_buffer,owner,a),BV_LIFETIME);bv_test_result(e,descriptor_two(e,bv_destroy_image_view,owner,view),BV_LIFETIME);bv_test_result(e,descriptor_two(e,bv_destroy_sampler,owner,sampler),BV_LIFETIME);bv_test_result(e,descriptor_two(e,bv_destroy_descriptor_set_layout,owner,schema),BV_LIFETIME);
  BvRow* alias=bv_get(bv_key(e,bv_test_value(e,bv_create_buffer(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(BufferCreateInfo),3,(Term[]){16,0,16})},NULL))),BV_BUFFER);
  bv_test_result(e,bv_bind_buffer_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(alias),bv_test_handle(bv_bound_memory(a)),bv_words(e,0)},NULL),0);
  assert(alias!=a && bv_bound_memory(alias)==bv_bound_memory(a));
  BvRow* commands=bv_test_pool(e,owner),*command=bv_test_command(e,owner,commands),*other=bv_test_command(e,owner,commands),*fence=bv_test_fence(e,owner);
  BvRow* layout=bv_get(bv_key(e,bv_test_value(e,bv_create_pipeline_layout(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(PipelineLayoutCreateInfo),4,(Term[]){descriptor_list(e,bv_test_handle(schema)),0,0,0})},NULL))),BV_LAYOUT),*pipeline=bv_add(BV_PIPELINE,owner);assert(layout && pipeline);
  assert(bv_stage_edge(&pipeline->deps,layout,BV_DEP_PIPELINE_LAYOUT));
  bv_test_one(e,bv_begin_command_buffer,command,0);bv_test_result(e,graphics_bind_call(e,command,pipeline),0);
  native=descriptor_bind_calls;before=bv_test_live_allocations;bv_test_alloc_at=0;bv_test_alloc_fail=1;
  bv_test_result(e,descriptor_bind_call(e,command,set,0),BV_LIMIT);assert(!command->command.sets[0] && descriptor_bind_calls==native && bv_test_live_allocations==before);bv_test_alloc_fail=0;
  bv_test_result(e,descriptor_bind_call(e,command,sampled,0),BV_ARGUMENT);bv_test_result(e,descriptor_bind_call(e,command,set,1),BV_ARGUMENT);
  BvDescriptorSlotTag tag=old[0].tag;old[0].tag=BV_UNWRITTEN_UNIFORM;bv_test_result(e,descriptor_bind_call(e,command,set,0),BV_LIFETIME);old[0].tag=tag;
  bv_test_result(e,descriptor_bind_call(e,command,set,0),0);
  BvDep* previous_recording=command->deps;native=descriptor_bind_calls;bv_test_alloc_at=0;bv_test_alloc_fail=1;
  bv_test_result(e,descriptor_bind_call(e,command,second,0),BV_LIMIT);bv_test_alloc_fail=0;
  assert(command->command.sets[0]==set && command->deps==previous_recording && descriptor_bind_calls==native);
  bv_test_result(e,descriptor_bind_call(e,command,second,0),0);assert(bv_referenced(set) && command->command.sets[0]==second);
  bv_test_result(e,graphics_bind_call(e,command,pipeline),0);assert(!command->command.sets[0] && bv_referenced(set));
  bv_test_one(e,bv_begin_command_buffer,other,0);bv_test_result(e,graphics_bind_call(e,other,pipeline),0);bv_test_result(e,descriptor_bind_call(e,other,set,0),0);
  BvDep* recorded=command->deps;
  const BvCommandPhase phases[]={BV_RECORDING,BV_EXECUTABLE,BV_PENDING,BV_UNCERTAIN,BV_COMPLETED,BV_COMMAND_INVALID};
  for(unsigned j=0;j<6;j++) {
    command->command.phase=phases[j];if(phases[j]==BV_PENDING)command->command.submission.pending.fence=fence;if(phases[j]==BV_UNCERTAIN)command->command.submission.uncertain.fence=fence;
    unsigned frees=descriptor_free_calls,resets=descriptor_reset_calls,destroys=descriptor_destroy_calls;
    descriptor_update_uniform(e,owner,set,b,a,3,0,0,16,BV_LIFETIME);
    bv_test_result(e,descriptor_two(e,bv_free_descriptor_set,owner,set),BV_LIFETIME);bv_test_result(e,descriptor_two(e,bv_reset_descriptor_pool,owner,pool),BV_LIFETIME);bv_test_result(e,descriptor_two(e,bv_destroy_descriptor_pool,owner,pool),BV_LIFETIME);
    assert(pool->object.descriptor_pool.sets==3 && pool->object.descriptor_pool.used_uniforms==4 && pool->object.descriptor_pool.used_sampled==1 && command->deps==recorded && set->object.set.slots==old && descriptor_free_calls==frees && descriptor_reset_calls==resets && descriptor_destroy_calls==destroys);
    if(phases[j]==BV_COMPLETED) {
      assert(!bv_memory_busy(bv_bound_memory(a)) && bv_referenced(set));
      bv_test_result(e,bv_write_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(bv_bound_memory(a)),bv_words(e,0),descriptor_list(e,0)},NULL),0);
    }
    if(phases[j]==BV_PENDING || phases[j]==BV_UNCERTAIN) {
      assert(bv_memory_busy(bv_bound_memory(alias)) && bv_memory_busy(bv_bound_memory(a)) && bv_memory_busy(bv_bound_memory(b)) && !bv_memory_busy(unrelated));
      bv_test_result(e,bv_write_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(bv_bound_memory(a)),bv_words(e,0),descriptor_list(e,0)},NULL),BV_LIFETIME);
      bv_test_result(e,bv_read_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(bv_bound_memory(b)),bv_words(e,0),1},NULL),BV_LIFETIME);
      bv_test_result(e,bv_write_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(unrelated),bv_words(e,0),descriptor_list(e,173)},NULL),0);
      Term actual=bv_test_value(e,bv_read_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(unrelated),bv_words(e,0),1},NULL)),bytes[2];bv_unpack(e,actual,2,bytes);assert(bytes[0]==173 && term_aux(bytes[1])==CID(Nil));
      bv_test_one(e,bv_reset_command_buffer,command,BV_LIFETIME);
    }
  }
  command->command.phase=BV_EXECUTABLE;d->ResetCommandBuffer=bv_test_reset_error;bv_test_one(e,bv_reset_command_buffer,command,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
  assert(command->deps==recorded && bv_referenced(set));d->ResetCommandBuffer=saved.ResetCommandBuffer;
  bv_test_one(e,bv_reset_command_buffer,command,0);descriptor_update_uniform(e,owner,set,b,a,3,0,0,16,BV_LIFETIME);
  bv_test_one(e,bv_reset_command_buffer,other,0);descriptor_update_uniform(e,owner,set,b,a,3,0,0,16,0);
  assert(set->object.set.slots[0].data.uniform.buffer==b && set->object.set.slots[1].data.uniform.buffer==a);
  bv_test_one(e,bv_begin_command_buffer,command,0);assert(bv_prepare_refs(command,1,&sampled));command->command.phase=BV_PENDING;command->command.submission.pending.fence=fence;
  assert(bv_memory_busy(bv_bound_memory(image)) && !bv_memory_busy(unrelated));
  bv_test_result(e,bv_read_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(bv_bound_memory(image)),bv_words(e,0),1},NULL),BV_LIFETIME);
  command->command.phase=BV_UNCERTAIN;command->command.submission.uncertain.fence=fence;assert(bv_memory_busy(bv_bound_memory(image)));
  command->command.phase=BV_COMPLETED;assert(!bv_memory_busy(bv_bound_memory(image)) && bv_referenced(sampled));bv_test_one(e,bv_reset_command_buffer,command,0);
  BvRow* fb=bv_add(BV_FRAMEBUFFER,owner);assert(fb);fb->object.framebuffer.count=1;BvDep view_edge={.target=view};BvDep* attachments[]={&view_edge};fb->object.framebuffer.attachments=attachments;
  assert(bv_descriptor_feedback(sampled,fb));
  bv_test_one(e,bv_begin_command_buffer,command,0);bv_test_result(e,graphics_bind_call(e,command,pipeline),0);
  layout->object.layout.sets[0]=sampled_schema;command->command.submission.recording.scope=(BvRenderScope){.tag=BV_INSIDE,.data.inside={fb}};
  native=descriptor_bind_calls;bv_test_result(e,descriptor_bind_call(e,command,sampled,0),BV_LIFETIME);assert(descriptor_bind_calls==native);
  command->command.submission.recording.scope.tag=BV_OUTSIDE;layout->object.layout.sets[0]=schema;bv_test_one(e,bv_reset_command_buffer,command,0);
  fb->object.framebuffer.attachments=NULL;bv_remove(fb);
  bv_test_result(e,descriptor_two(e,bv_destroy_command_pool,owner,commands),0);bv_test_result(e,descriptor_two(e,bv_destroy_fence,owner,fence),0);bv_remove(pipeline);bv_test_result(e,descriptor_two(e,bv_destroy_pipeline_layout,owner,layout),0);
  bv_test_result(e,descriptor_two(e,bv_free_descriptor_set,owner,second),0);
  descriptor_update_uniform(e,owner,set,a,a,3,0,0,16,0);assert(bv_referenced(a) && !bv_referenced(b));
  descriptor_update_uniform(e,owner,set,b,b,3,0,0,16,0);assert(!bv_referenced(a) && bv_referenced(b));
  BvRow* quarantine_commands=bv_test_pool(e,owner),*quarantine_command=bv_test_command(e,owner,quarantine_commands),*quarantine_fence=bv_test_fence(e,owner);
  bv_test_one(e,bv_begin_command_buffer,quarantine_command,0);assert(bv_prepare_refs(quarantine_command,1,&sampled));bv_test_one(e,bv_end_command_buffer,quarantine_command,0);
  descriptor_native_result=VK_ERROR_UNKNOWN;before=bv_test_live_allocations;uint32_t old_sets=pool->object.descriptor_pool.sets;
  bv_test_result(e,descriptor_two(e,bv_free_descriptor_set,owner,set),(uint32_t)VK_ERROR_UNKNOWN);
  assert(pool->object.descriptor_pool.phase==BV_POOL_QUARANTINED && pool->object.descriptor_pool.sets==old_sets && bv_test_live_allocations==before && bv_referenced(b));
  bv_test_submit_call(e,owner,quarantine_command,quarantine_fence,BV_LIFETIME);
  bv_test_result(e,descriptor_two(e,bv_destroy_command_pool,owner,quarantine_commands),0);bv_test_result(e,descriptor_two(e,bv_destroy_fence,owner,quarantine_fence),0);
  descriptor_update_uniform(e,owner,set,a,b,3,0,0,16,BV_LIFETIME);bv_test_result(e,descriptor_two(e,bv_reset_descriptor_pool,owner,pool),BV_LIFETIME);
  bv_test_result(e,descriptor_two(e,bv_destroy_descriptor_pool,owner,pool),0);descriptor_native_result=VK_SUCCESS;
  pool=bv_get(bv_key(e,bv_test_value(e,bv_create_descriptor_pool(e,(Term[]){bv_test_handle(owner),descriptor_pool_info(e,1,2,0)},NULL))),BV_DESCRIPTOR_POOL);
  set=descriptor_set_new(e,owner,pool,schema);descriptor_update_uniform(e,owner,set,a,b,3,0,0,16,0);uint32_t stale=set->id;
  descriptor_native_result=VK_ERROR_OUT_OF_HOST_MEMORY;before=bv_test_live_allocations;
  bv_test_result(e,descriptor_two(e,bv_reset_descriptor_pool,owner,pool),(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
  assert(bv_get(stale,BV_DESCRIPTOR_SET)==set && pool->object.descriptor_pool.phase==BV_POOL_QUARANTINED && bv_test_live_allocations==before && bv_referenced(a));
  bv_test_result(e,descriptor_two(e,bv_destroy_descriptor_pool,owner,pool),0);descriptor_native_result=VK_SUCCESS;
  pool=bv_get(bv_key(e,bv_test_value(e,bv_create_descriptor_pool(e,(Term[]){bv_test_handle(owner),descriptor_pool_info(e,1,2,0)},NULL))),BV_DESCRIPTOR_POOL);
  set=descriptor_set_new(e,owner,pool,schema);stale=set->id;bv_test_result(e,descriptor_two(e,bv_reset_descriptor_pool,owner,pool),0);
  assert(!bv_get(stale,BV_DESCRIPTOR_SET) && !pool->object.descriptor_pool.sets);bv_test_result(e,bv_free_descriptor_set(e,(Term[]){bv_test_handle(owner),term_pak(CID(DescriptorSet),stale)},NULL),BV_INVALID);
  bv_test_result(e,descriptor_two(e,bv_destroy_descriptor_pool,owner,pool),0);
  bv_test_result(e,descriptor_two(e,bv_destroy_sampler,owner,sampler),0);bv_test_result(e,descriptor_two(e,bv_destroy_descriptor_set_layout,owner,schema),0);bv_test_result(e,descriptor_two(e,bv_destroy_descriptor_set_layout,owner,sampled_schema),0);
  bv_test_result(e,descriptor_two(e,bv_destroy_buffer,owner,alias),0);
  *d=saved;assert(bv_test_live_allocations==allocations);
  puts("Controlled descriptor metadata sweeps, limits, typed rollback, freeze phases, multiple commands, transitive memory, unrelated memory, stale budgets and quarantine passed");
}
static Term test_descriptor_layout(Env e,Term* f,IoWork* w) {
  static bool ran;BvRow* owner=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_DEVICE);
  if(!ran && owner) {ran=true;descriptor_probes(e,owner);}
  return bv_create_descriptor_set_layout(e,f,w);
}

static Term test_descriptor_roundtrip(Env e,Term* f,IoWork* w) {
  uint64_t value=bv_u64(e,f[0]);
  if(value==3735928556u)return io_done(e,bv_words(e,UINT64_C(1)<<32));
  if(value==3735928557u) {descriptor_fail_update=true;return io_done(e,bv_words(e,value));}
  return io_done(e,bv_words(e,value));
}
static Term test_descriptor_update(Env e,Term* f,IoWork* w) {
  if(!descriptor_fail_update)return bv_update_descriptor_set(e,f,w);
  descriptor_fail_update=false;BvRow* set=bv_get(bv_key(e,term_keep(e,f[1],1)),BV_DESCRIPTOR_SET);assert(set && !bv_referenced(set));
  BvDescriptorSlot* old=set->object.set.slots;BvDep* deps=set->deps;unsigned allocations=bv_test_live_allocations;
  bv_test_alloc_at=0;bv_test_alloc_fail=1;Term result=bv_update_descriptor_set(e,f,w);bv_test_alloc_fail=0;
  assert(set->object.set.slots==old && set->deps==deps && bv_test_live_allocations==allocations);return result;
}
