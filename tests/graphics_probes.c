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

static unsigned graphics_binds,graphics_vertices,graphics_indices,graphics_pushes,graphics_draws,graphics_viewports,graphics_scissors;
static VkDeviceSize graphics_offset;
static int32_t graphics_base;
static VKAPI_ATTR void VKAPI_CALL graphics_bind(VkCommandBuffer c,VkPipelineBindPoint point,VkPipeline p) {assert(point==VK_PIPELINE_BIND_POINT_GRAPHICS);graphics_binds++;}
static VKAPI_ATTR void VKAPI_CALL graphics_vertex(VkCommandBuffer c,uint32_t first,uint32_t count,const VkBuffer* b,const VkDeviceSize* offset) {assert(first==0 && count==1);graphics_offset=*offset;graphics_vertices++;}
static VKAPI_ATTR void VKAPI_CALL graphics_index(VkCommandBuffer c,VkBuffer b,VkDeviceSize offset,VkIndexType type) {graphics_offset=offset;assert(type==0 || type==1);graphics_indices++;}
static VKAPI_ATTR void VKAPI_CALL graphics_push(VkCommandBuffer c,VkPipelineLayout layout,VkShaderStageFlags stages,uint32_t offset,uint32_t bytes,const void* p) {assert(stages==1 && !offset && bytes==64 && ((const uint32_t*)p)[0]==0x3f800000);graphics_pushes++;}
static VKAPI_ATTR void VKAPI_CALL graphics_draw(VkCommandBuffer c,uint32_t count,uint32_t instances,uint32_t first,int32_t base,uint32_t instance) {assert(count==3 && instances==1 && first==1 && instance==2);graphics_base=base;graphics_draws++;}
static VKAPI_ATTR void VKAPI_CALL graphics_viewport(VkCommandBuffer c,uint32_t first,uint32_t count,const VkViewport* v) {assert(!first && count==1 && v->width==8 && v->height==4);graphics_viewports++;}
static VKAPI_ATTR void VKAPI_CALL graphics_scissor(VkCommandBuffer c,uint32_t first,uint32_t count,const VkRect2D* s) {assert(!first && count==1 && s->extent.width==8 && s->extent.height==4);graphics_scissors++;}
static Term graphics_bind_call(Env e,BvRow* command,BvRow* pipeline) {return bv_cmd_bind_graphics_pipeline(e,(Term[]){bv_test_handle(command),bv_test_handle(pipeline)},NULL);}
static Term graphics_vertex_call(Env e,BvRow* command,BvRow* buffer,uint64_t offset) {return bv_cmd_bind_vertex_buffer(e,(Term[]){bv_test_handle(command),0,bv_test_handle(buffer),bv_words(e,offset)},NULL);}
static Term graphics_index_call(Env e,BvRow* command,BvRow* buffer,uint64_t offset,uint32_t type) {return bv_cmd_bind_index_buffer(e,(Term[]){bv_test_handle(command),bv_test_handle(buffer),bv_words(e,offset),type},NULL);}
static Term graphics_push_call(Env e,BvRow* command,unsigned count) {
  Term list=term_pak(CID(Nil),0);for(unsigned j=0;j<count;j++)list=io_node(e,CID(Con),0x3f800000,list);
  return bv_cmd_push_constants(e,(Term[]){bv_test_handle(command),list},NULL);
}
static Term graphics_draw_call(Env e,BvRow* command,uint32_t first,uint32_t base) {
  return bv_cmd_draw_indexed(e,(Term[]){bv_test_handle(command),bv_node(e,CID(IndexedDraw),5,(Term[]){3,1,first,base,2})},NULL);
}
static void graphics_current_unchanged(BvRow* command,BvRecording* before,BvDep* deps) {assert(!memcmp(before,&command->command.submission.recording,sizeof(*before)) && command->deps==deps);}
static void graphics_command_probes(Env e,BvRow* owner,BvRow* pipeline) {
  BvDevice* d=owner->context;BvDevice saved=*d;unsigned allocations=bv_test_live_allocations;
  BvRow *vertices=NULL,*indices=NULL,*second=NULL,*framebuffer=NULL;
  for(BvRow* row=bv_rows;row;row=row->next)if(row->parent==owner) {
    if(row->kind==BV_BUFFER && (row->flags&128)) vertices=row;
    if(row->kind==BV_BUFFER && (row->flags&64)) {if(!indices)indices=row;else second=row;}
    if(row->kind==BV_FRAMEBUFFER)framebuffer=row;
  }
  assert(vertices && indices && second && framebuffer);
  BvRow* pool=bv_test_pool(e,owner),*command=bv_test_command(e,owner,pool),*fence=bv_test_fence(e,owner);
  d->CmdBindPipeline=graphics_bind;d->CmdBindVertexBuffers=graphics_vertex;d->CmdBindIndexBuffer=graphics_index;
  d->CmdPushConstants=graphics_push;d->CmdDrawIndexed=graphics_draw;d->CmdSetViewport=graphics_viewport;d->CmdSetScissor=graphics_scissor;
  d->CmdBeginRenderPass=probe_begin_pass;d->CmdEndRenderPass=probe_end_pass;
  bv_test_result(e,graphics_bind_call(e,command,pipeline),BV_LIFETIME);
  bv_test_one(e,bv_begin_command_buffer,command,0);
  BvRecording before=command->command.submission.recording;BvDep* deps=command->deps;
  bv_test_alloc_at=0;bv_test_alloc_fail=1;
  bv_test_result(e,graphics_bind_call(e,command,pipeline),BV_LIMIT);assert(!graphics_binds);graphics_current_unchanged(command,&before,deps);
  bv_test_alloc_fail=0;bv_test_result(e,graphics_bind_call(e,command,pipeline),0);
  bv_test_result(e,graphics_draw_call(e,command,1,0),BV_LIFETIME);
  bv_test_result(e,probe_begin_call(e,command,framebuffer),0);
  bv_test_result(e,graphics_draw_call(e,command,1,0),BV_LIFETIME);
  bv_test_result(e,bv_cmd_set_viewport(e,(Term[]){bv_test_handle(command),bv_node(e,CID(Viewport),6,(Term[]){0,0,f32_rewrap(8),f32_rewrap(4),0,f32_rewrap(1)})},NULL),0);
  bv_test_result(e,bv_cmd_set_scissor(e,(Term[]){bv_test_handle(command),bv_node(e,CID(RenderArea),4,(Term[]){0,0,8,4})},NULL),0);
  before=command->command.submission.recording;deps=command->deps;
  bv_test_alloc_at=0;bv_test_alloc_fail=1;
  bv_test_result(e,graphics_vertex_call(e,command,vertices,16),BV_LIMIT);assert(!graphics_vertices);graphics_current_unchanged(command,&before,deps);
  bv_test_alloc_at=0;bv_test_result(e,graphics_index_call(e,command,indices,8,0),BV_LIMIT);assert(!graphics_indices);graphics_current_unchanged(command,&before,deps);
  bv_test_alloc_fail=0;bv_test_realloc_at=0;bv_test_realloc_fail=1;
  bv_test_result(e,graphics_push_call(e,command,16),BV_LIMIT);assert(!graphics_pushes);graphics_current_unchanged(command,&before,deps);
  bv_test_realloc_fail=0;
  bv_test_result(e,graphics_vertex_call(e,command,vertices,17),BV_ARGUMENT);
  bv_test_result(e,graphics_vertex_call(e,command,vertices,vertices->size-4),BV_ARGUMENT);
  bv_test_result(e,graphics_vertex_call(e,command,vertices,UINT64_C(1)<<32),BV_ARGUMENT);
  bv_test_result(e,graphics_index_call(e,command,indices,9,0),BV_ARGUMENT);
  bv_test_result(e,graphics_index_call(e,command,indices,8,2),BV_ARGUMENT);
  bv_test_result(e,graphics_index_call(e,command,indices,UINT64_C(1)<<32,1),BV_ARGUMENT);
  bv_test_result(e,graphics_push_call(e,command,15),BV_ARGUMENT);bv_test_result(e,graphics_push_call(e,command,17),BV_ARGUMENT);
  graphics_current_unchanged(command,&before,deps);assert(!graphics_vertices && !graphics_indices && !graphics_pushes);
  uint64_t vertex_size=vertices->size,index_size=indices->size;vertices->size=indices->size=(UINT64_C(1)<<32)+256;
  bv_test_result(e,graphics_vertex_call(e,command,vertices,(UINT64_C(1)<<32)+16),0);assert(graphics_offset==(UINT64_C(1)<<32)+16);
  bv_test_result(e,graphics_index_call(e,command,indices,(UINT64_C(1)<<32)+8,1),0);assert(graphics_offset==(UINT64_C(1)<<32)+8);
  vertices->size=vertex_size;indices->size=index_size;
  bv_test_result(e,graphics_vertex_call(e,command,vertices,16),0);bv_test_result(e,graphics_index_call(e,command,indices,8,0),0);
  bv_test_result(e,graphics_draw_call(e,command,1,0),BV_LIFETIME);
  bv_test_result(e,graphics_push_call(e,command,16),0);
  bv_test_result(e,graphics_draw_call(e,command,UINT32_MAX,0),BV_ARGUMENT);
  bv_test_result(e,graphics_draw_call(e,command,1,UINT32_MAX-2),0);assert(graphics_base==-3);
  bv_test_result(e,graphics_draw_call(e,command,1,0x80000000),0);assert(graphics_base==INT32_MIN);
  bv_test_result(e,graphics_bind_call(e,command,pipeline),0);
  assert(!command->command.submission.recording.vertices_ready && !command->command.submission.recording.push_ready);
  bv_test_result(e,graphics_draw_call(e,command,1,0),BV_LIFETIME);
  uint32_t flags=second->flags;second->flags|=128;
  bv_test_result(e,graphics_vertex_call(e,command,second,16),0);bv_test_result(e,graphics_index_call(e,command,second,8,1),0);
  second->flags=flags;
  bv_test_result(e,graphics_push_call(e,command,16),0);
  bv_test_one(e,bv_cmd_end_render_pass,command,0);assert(command->command.submission.recording.viewport_ready && command->command.submission.recording.index_ready);
  bv_test_one(e,bv_end_command_buffer,command,0);
  assert(bv_referenced(vertices) && bv_referenced(indices) && bv_referenced(second) && bv_referenced(pipeline));
  d->QueueSubmit=bv_test_submit;d->GetFenceStatus=probe_status_not_ready;d->WaitForFences=bv_test_wait;d->DeviceWaitIdle=bv_test_idle_error;d->MapMemory=probe_graph_map;d->UnmapMemory=probe_graph_unmap;
  bv_test_submit_result=VK_SUCCESS;bv_test_submit_call(e,owner,command,fence,0);
  probe_graph_host_blocked(e,owner,bv_bound_memory(vertices));probe_graph_host_blocked(e,owner,bv_bound_memory(indices));probe_graph_host_blocked(e,owner,bv_bound_memory(second));
  bv_test_result(e,bv_destroy_graphics_pipeline(e,(Term[]){bv_test_handle(owner),bv_test_handle(pipeline)},NULL),BV_LIFETIME);
  bv_test_wait_result=VK_TIMEOUT;bv_test_status(e,bv_fence_wait(e,(Term[]){bv_test_handle(fence),bv_words(e,0)},NULL),VK_TIMEOUT);
  assert(bv_memory_busy(bv_bound_memory(vertices)));
  bv_test_wait_result=VK_SUCCESS;bv_test_status(e,bv_fence_wait(e,(Term[]){bv_test_handle(fence),bv_words(e,0)},NULL),VK_SUCCESS);
  assert(!bv_memory_busy(bv_bound_memory(vertices)) && bv_referenced(vertices));
  d->ResetCommandBuffer=bv_test_reset_error;bv_test_one(e,bv_reset_command_buffer,command,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);assert(bv_referenced(vertices) && bv_referenced(pipeline));
  d->ResetCommandBuffer=saved.ResetCommandBuffer;bv_test_one(e,bv_reset_command_buffer,command,0);assert(!command->deps);
  bv_test_one(e,bv_begin_command_buffer,command,0);bv_test_result(e,graphics_bind_call(e,command,pipeline),0);
  bv_test_result(e,graphics_vertex_call(e,command,vertices,16),0);bv_test_result(e,graphics_index_call(e,command,indices,8,1),0);
  bv_test_one(e,bv_end_command_buffer,command,0);bv_test_submit_result=VK_ERROR_UNKNOWN;
  bv_test_submit_call(e,owner,command,fence,(uint32_t)VK_ERROR_UNKNOWN);
  probe_graph_host_blocked(e,owner,bv_bound_memory(vertices));probe_graph_host_blocked(e,owner,bv_bound_memory(indices));
  bv_test_idle_result=VK_SUCCESS;bv_test_one(e,bv_device_wait_idle,owner,0);assert(command->command.phase==BV_COMMAND_INVALID && bv_referenced(vertices));
  bv_test_one(e,bv_reset_command_buffer,command,0);assert(!command->deps);
  *d=saved;
  bv_test_result(e,bv_destroy_command_pool(e,(Term[]){bv_test_handle(owner),bv_test_handle(pool)},NULL),0);
  bv_test_result(e,bv_destroy_fence(e,(Term[]){bv_test_handle(owner),bv_test_handle(fence)},NULL),0);
  assert(bv_test_live_allocations==allocations);
  puts("Controlled graphics readiness, signed extremes, U64 offsets, overwritten roots, pending/Uncertain host exclusion and failed-reset retention passed");
}
static Term test_bind_graphics_pipeline(Env e,Term* f,IoWork* w) {
  static int ran;
  if(!ran) {
    BvRow* command=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_COMMAND),*pipeline=bv_get(bv_key(e,term_keep(e,f[1],1)),BV_PIPELINE);
    if(command && pipeline) {ran=1;graphics_command_probes(e,bv_command_device(command),pipeline);}
  }
  return bv_cmd_bind_graphics_pipeline(e,f,w);
}
