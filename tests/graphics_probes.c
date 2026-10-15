static unsigned graphics_creates,graphics_destroys,graphics_shader_creates,graphics_layout_creates;
static VkResult graphics_result;
static VKAPI_ATTR VkResult VKAPI_CALL graphics_create(VkDevice d,VkPipelineCache cache,uint32_t count,const VkGraphicsPipelineCreateInfo* p,const VkAllocationCallbacks* a,VkPipeline* out) {
  graphics_creates++;assert(!cache && count==1 && !a && *out==VK_NULL_HANDLE);
  assert(p->stageCount==2 && p->renderPass && p->layout && !p->subpass && p->basePipelineIndex==-1);
  assert(!strcmp(p->pStages[0].pName,"main") && !strcmp(p->pStages[1].pName,"main"));
  assert(p->pStages[0].stage==1 && p->pStages[1].stage==16);
  assert(p->pRasterizationState->polygonMode==VK_POLYGON_MODE_FILL && p->pRasterizationState->lineWidth==1);
  assert(p->pMultisampleState->rasterizationSamples==1 && !p->pColorBlendState->pAttachments[0].blendEnable);
  assert(p->pDepthStencilState->depthTestEnable && p->pDepthStencilState->depthWriteEnable && p->pDepthStencilState->depthCompareOp==1);
  assert(p->pDynamicState->dynamicStateCount==2 && p->pViewportState->viewportCount==1 && p->pViewportState->scissorCount==1);
  *out=(VkPipeline)(uintptr_t)0x7788;return graphics_result;
}
static VKAPI_ATTR void VKAPI_CALL graphics_destroy(VkDevice d,VkPipeline p,const VkAllocationCallbacks* a) {assert((uintptr_t)p==0x7788);graphics_destroys++;}
static VKAPI_ATTR VkResult VKAPI_CALL graphics_shader(VkDevice d,const VkShaderModuleCreateInfo* p,const VkAllocationCallbacks* a,VkShaderModule* out) {
  graphics_shader_creates++;assert(p->codeSize==20 && p->pCode[0]==0x07230203 && *out==VK_NULL_HANDLE);return graphics_result;
}
static VKAPI_ATTR VkResult VKAPI_CALL graphics_layout(VkDevice d,const VkPipelineLayoutCreateInfo* p,const VkAllocationCallbacks* a,VkPipelineLayout* out) {
  graphics_layout_creates++;assert(p->pushConstantRangeCount==1 && p->pPushConstantRanges->size==64 && !p->pPushConstantRanges->offset && *out==VK_NULL_HANDLE);return graphics_result;
}
static Term graphics_words(Env e) {
  Term list=term_pak(CID(Nil),0);uint32_t words[]={0x07230203,0x10000,0,1,0};
  for(unsigned j=5;j>0;j--) list=io_node(e,CID(Con),words[j-1],list);return list;
}
static Term graphics_info_copy(Env e,Term info,int lane,Term replacement) {
  Term p[14];bv_unpack(e,term_keep(e,info,1),14,p);
  if(lane>=0) {term_sink(e,p[lane]);p[lane]=replacement;}
  return bv_node(e,CID(GraphicsPipelineCreateInfo),14,p);
}
static void graphics_resource_probes(Env e,BvRow* owner,Term info) {
  BvDevice* d=owner->context;
  PFN_vkCreateGraphicsPipelines create=d->CreateGraphicsPipelines;PFN_vkDestroyPipeline destroy=d->DestroyPipeline;
  PFN_vkCreateShaderModule shader=d->CreateShaderModule;PFN_vkCreatePipelineLayout layout=d->CreatePipelineLayout;
  d->CreateGraphicsPipelines=graphics_create;d->DestroyPipeline=graphics_destroy;
  d->CreateShaderModule=graphics_shader;d->CreatePipelineLayout=graphics_layout;
  unsigned allocations=bv_test_live_allocations;
  for(unsigned fail=1;fail<=5;fail++) {
    bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    bv_test_result(e,bv_create_graphics_pipeline(e,(Term[]){bv_test_handle(owner),graphics_info_copy(e,info,-1,0)},NULL),BV_LIMIT);
    assert(!graphics_creates && bv_test_live_allocations==allocations);
  }
  bv_test_alloc_fail=0;graphics_result=VK_ERROR_INITIALIZATION_FAILED;
  bv_test_result(e,bv_create_graphics_pipeline(e,(Term[]){bv_test_handle(owner),graphics_info_copy(e,info,-1,0)},NULL),(uint32_t)graphics_result);
  assert(graphics_creates==1 && graphics_destroys==1 && bv_test_live_allocations==allocations);
  const unsigned lanes[]={0,1,2,6,7,8,12,13};const uint32_t values[]={0,0,0,0,4,2,8,16};
  for(unsigned j=0;j<8;j++) {
    bv_test_result(e,bv_create_graphics_pipeline(e,(Term[]){bv_test_handle(owner),graphics_info_copy(e,info,lanes[j],values[j])},NULL),j<3 ? BV_INVALID : BV_ARGUMENT);
    assert(graphics_creates==1 && bv_test_live_allocations==allocations);
  }
  {
    bv_test_alloc_at=0;bv_test_alloc_fail=1;
    bv_test_result(e,bv_create_shader_module(e,(Term[]){bv_test_handle(owner),graphics_words(e)},NULL),BV_LIMIT);
    bv_test_alloc_at=0;
    bv_test_result(e,bv_create_pipeline_layout(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(PipelineLayoutCreateInfo),3,(Term[]){1,1,64})},NULL),BV_LIMIT);
  }
  bv_test_alloc_fail=0;bv_test_realloc_at=0;bv_test_realloc_fail=1;
  bv_test_result(e,bv_create_shader_module(e,(Term[]){bv_test_handle(owner),graphics_words(e)},NULL),BV_LIMIT);
  bv_test_realloc_fail=0;assert(!graphics_shader_creates && !graphics_layout_creates);
  bv_test_result(e,bv_create_shader_module(e,(Term[]){bv_test_handle(owner),graphics_words(e)},NULL),(uint32_t)graphics_result);
  bv_test_result(e,bv_create_pipeline_layout(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(PipelineLayoutCreateInfo),3,(Term[]){1,1,64})},NULL),(uint32_t)graphics_result);
  assert(graphics_shader_creates==1 && graphics_layout_creates==1 && bv_test_live_allocations==allocations);
  d->CreateGraphicsPipelines=create;d->DestroyPipeline=destroy;d->CreateShaderModule=shader;d->CreatePipelineLayout=layout;
  puts("Controlled graphics creation allocation-before-dispatch, exact errors and nonnull failed output rollback passed");
}
static Term test_create_graphics_pipeline(Env e,Term* f,IoWork* w) {
  static int ran;BvRow* owner=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_DEVICE);
  if (!ran && owner) {
    Term p[14];bv_unpack(e,term_keep(e,f[1],1),14,p);int valid=bv_child(p[0],BV_LAYOUT,owner)!=NULL;
    for(unsigned j=0;j<14;j++)term_sink(e,p[j]);
    if(valid) {ran=1;graphics_resource_probes(e,owner,f[1]);}
  }
  return bv_create_graphics_pipeline(e,f,w);
}
