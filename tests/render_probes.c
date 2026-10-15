static unsigned probe_pass_creates,probe_pass_destroys,probe_fb_creates,probe_fb_destroys,probe_begins,probe_ends,probe_maps;
static VkResult probe_render_result=VK_SUCCESS;
static VKAPI_ATTR VkResult VKAPI_CALL probe_create_pass(VkDevice d,const VkRenderPassCreateInfo* p,const VkAllocationCallbacks* a,VkRenderPass* out) {
  probe_pass_creates++;assert(p->sType==VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO && !p->pNext && !a && !p->flags);
  assert(p->attachmentCount==2 && p->subpassCount==1 && !p->dependencyCount && p->pSubpasses[0].pipelineBindPoint==VK_PIPELINE_BIND_POINT_GRAPHICS);
  assert(p->pSubpasses[0].colorAttachmentCount==1 && p->pSubpasses[0].pColorAttachments[0].attachment==0 && p->pSubpasses[0].pColorAttachments[0].layout==2);
  assert(p->pSubpasses[0].pDepthStencilAttachment->attachment==1 && p->pSubpasses[0].pDepthStencilAttachment->layout==3);
  for(unsigned j=0;j<2;j++) {
    VkAttachmentDescription v=p->pAttachments[j];assert(v.samples==1 && v.loadOp==1 && v.storeOp==0 && !v.flags);
    assert(v.initialLayout==(j ? 3 : 2) && v.finalLayout==v.initialLayout && v.stencilLoadOp==2 && v.stencilStoreOp==1);
  }
  *out=(VkRenderPass)(uintptr_t)0x123;return probe_render_result;
}
static VKAPI_ATTR void VKAPI_CALL probe_destroy_pass(VkDevice d,VkRenderPass p,const VkAllocationCallbacks* a) {probe_pass_destroys++;}
static VKAPI_ATTR VkResult VKAPI_CALL probe_create_fb(VkDevice d,const VkFramebufferCreateInfo* p,const VkAllocationCallbacks* a,VkFramebuffer* out) {
  probe_fb_creates++;assert(p->sType==VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO && !p->pNext && !p->flags && !a);
  assert(p->attachmentCount==2 && p->width==8 && p->height==4 && p->layers==1 && p->renderPass);
  *out=(VkFramebuffer)(uintptr_t)0x456;return probe_render_result;
}
static VKAPI_ATTR void VKAPI_CALL probe_destroy_fb(VkDevice d,VkFramebuffer p,const VkAllocationCallbacks* a) {probe_fb_destroys++;}
static VKAPI_ATTR void VKAPI_CALL probe_begin_pass(VkCommandBuffer c,const VkRenderPassBeginInfo* p,VkSubpassContents contents) {
  probe_begins++;assert(p->sType==VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO && !p->pNext && contents==VK_SUBPASS_CONTENTS_INLINE);
  assert(p->renderArea.offset.x==0 && p->renderArea.offset.y==0 && p->renderArea.extent.width==8 && p->renderArea.extent.height==4 && p->clearValueCount==2);
  assert(p->pClearValues[0].color.float32[2]==1 && p->pClearValues[0].color.float32[3]==1);
  uint32_t bits;memcpy(&bits,&p->pClearValues[1].depthStencil.depth,4);assert(bits==0x3f000000 && !p->pClearValues[1].depthStencil.stencil);
}
static VKAPI_ATTR void VKAPI_CALL probe_end_pass(VkCommandBuffer c) {probe_ends++;}
static VKAPI_ATTR VkResult VKAPI_CALL probe_graph_map(VkDevice d,VkDeviceMemory m,VkDeviceSize o,VkDeviceSize n,VkMemoryMapFlags f,void** out) {
  static unsigned char byte=90;probe_maps++;*out=&byte;return VK_SUCCESS;
}
static VKAPI_ATTR void VKAPI_CALL probe_graph_unmap(VkDevice d,VkDeviceMemory m) {}
static VKAPI_ATTR VkResult VKAPI_CALL probe_status_not_ready(VkDevice d,VkFence f) {return VK_NOT_READY;}
static Term probe_pass_info(Env e) {
  return bv_node(e,CID(RenderPassCreateInfo),5,(Term[]){io_node(e,CID(Con),bv_node(e,CID(AttachmentInfo),3,(Term[]){37,1,0}),term_pak(CID(Nil),0)),1,126,1,0});
}
static Term probe_fb_info(Env e,BvRow* framebuffer) {
  BvFramebuffer* fb=&framebuffer->object.framebuffer;Term list=term_pak(CID(Nil),0);
  for(unsigned j=fb->count;j>0;j--)list=io_node(e,CID(Con),term_pak(CID(ImageView),fb->attachments[j-1]->target->id),list);
  return bv_node(e,CID(FramebufferCreateInfo),4,(Term[]){bv_dependency(framebuffer,BV_DEP_FRAMEBUFFER_PASS)->target->id,list,8,4});
}
static Term probe_begin_call(Env e,BvRow* command,BvRow* framebuffer) {
  Term clears=io_node(e,CID(Con),bv_node(e,CID(ColorClear),4,(Term[]){0,0,f32_rewrap(1),f32_rewrap(1)}),
    io_node(e,CID(Con),term_pak(CID(DepthClear),0x3f000000),term_pak(CID(Nil),0)));
  return bv_cmd_begin_render_pass(e,(Term[]){bv_test_handle(command),bv_test_handle(framebuffer),bv_node(e,CID(RenderArea),4,(Term[]){0,0,8,4}),clears},NULL);
}
static unsigned probe_scope_commands;
static VKAPI_ATTR void VKAPI_CALL probe_scope_fill(VkCommandBuffer c,VkBuffer b,VkDeviceSize o,VkDeviceSize n,uint32_t v) {probe_scope_commands++;}
static void probe_graph_retained(Env e,BvRow* owner,BvRow* framebuffer) {
  bv_test_result(e,bv_destroy_framebuffer(e,(Term[]){bv_test_handle(owner),bv_test_handle(framebuffer)},NULL),BV_LIFETIME);
  bv_test_result(e,bv_destroy_render_pass(e,(Term[]){bv_test_handle(owner),bv_test_handle(bv_dependency(framebuffer,BV_DEP_FRAMEBUFFER_PASS)->target)},NULL),BV_LIFETIME);
  for(unsigned j=0;j<framebuffer->object.framebuffer.count;j++) {
    BvRow* view=framebuffer->object.framebuffer.attachments[j]->target;
    BvRow* image=bv_dependency(view,BV_DEP_VIEW_IMAGE)->target;
    bv_test_result(e,bv_destroy_image_view(e,(Term[]){bv_test_handle(owner),bv_test_handle(view)},NULL),BV_LIFETIME);
    bv_test_result(e,bv_destroy_image(e,(Term[]){bv_test_handle(owner),bv_test_handle(image)},NULL),BV_LIFETIME);
    bv_test_result(e,bv_free_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(bv_bound_memory(image))},NULL),BV_LIFETIME);
  }
}
static void probe_graph_host_blocked(Env e,BvRow* owner,BvRow* memory) {
  unsigned maps=probe_maps;
  bv_test_result(e,bv_read_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(memory),bv_words(e,0),1},NULL),BV_LIFETIME);
  bv_test_result(e,bv_write_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(memory),bv_words(e,0),io_node(e,CID(Con),91,term_pak(CID(Nil),0))},NULL),BV_LIFETIME);
  bv_test_upload_result(e,owner,memory,false,BV_LIFETIME);
  bv_test_upload_result(e,owner,memory,true,BV_LIFETIME);
  assert(probe_maps==maps);
}
static void probe_outside_guards(Env e,BvRow* command,BvRow* framebuffer) {
  BvRow* owner=bv_command_device(command);BvDevice* d=owner->context;BvRow* buffer=NULL;
  for(BvRow* r=bv_rows;r;r=r->next)if(r->kind==BV_BUFFER && r->parent==owner && bv_bound_memory(r))buffer=r;
  assert(buffer);BvRow* color=bv_dependency(framebuffer->object.framebuffer.attachments[0]->target,BV_DEP_VIEW_IMAGE)->target;
  BvRow* depth=bv_dependency(framebuffer->object.framebuffer.attachments[1]->target,BV_DEP_VIEW_IMAGE)->target;
  PFN_vkCmdFillBuffer fill=d->CmdFillBuffer;PFN_vkCmdCopyBuffer copy=d->CmdCopyBuffer;PFN_vkCmdPipelineBarrier barrier=d->CmdPipelineBarrier;
  PFN_vkCmdClearColorImage cc=d->CmdClearColorImage;PFN_vkCmdClearDepthStencilImage cd=d->CmdClearDepthStencilImage;
  PFN_vkCmdCopyBufferToImage up=d->CmdCopyBufferToImage;PFN_vkCmdCopyImageToBuffer down=d->CmdCopyImageToBuffer;
  PFN_vkEndCommandBuffer end=d->EndCommandBuffer;
  d->CmdFillBuffer=probe_scope_fill;d->CmdCopyBuffer=bv_test_copy;d->CmdPipelineBarrier=bv_test_barrier;
  d->CmdClearColorImage=probe_clear_color;d->CmdClearDepthStencilImage=probe_clear_depth;d->CmdCopyBufferToImage=probe_copy_upload;d->CmdCopyImageToBuffer=probe_copy_download;d->EndCommandBuffer=bv_test_end_error;
  unsigned calls=probe_scope_commands+probe_image_commands+bv_test_copy_calls+bv_test_barrier_calls;
  bv_test_result(e,bv_cmd_fill_buffer(e,(Term[]){bv_test_handle(command),bv_test_handle(buffer),bv_words(e,0),bv_words(e,4),0},NULL),BV_LIFETIME);
  bv_test_result(e,bv_cmd_copy_buffer(e,(Term[]){bv_test_handle(command),bv_test_handle(buffer),bv_test_handle(buffer),bv_test_regions(e,0,8,4)},NULL),BV_LIFETIME);
  bv_test_result(e,bv_cmd_pipeline_barrier(e,(Term[]){bv_test_handle(command),4096,4096,term_pak(CID(Nil),0),term_pak(CID(Nil),0),term_pak(CID(Nil),0)},NULL),BV_LIFETIME);
  bv_test_result(e,probe_clear_call(e,command,color),BV_LIFETIME);
  bv_test_result(e,bv_cmd_clear_depth_image(e,(Term[]){bv_test_handle(command),bv_test_handle(depth),7,f32_rewrap(0.5f),probe_range_list(e,2)},NULL),BV_LIFETIME);
  bv_test_result(e,probe_transfer_call(e,command,color,buffer,1,1,0,0,3,2),BV_LIFETIME);
  bv_test_result(e,probe_transfer_call(e,command,color,buffer,0,1,0,0,3,2),BV_LIFETIME);
  bv_test_one(e,bv_end_command_buffer,command,BV_LIFETIME);
  assert(calls==probe_scope_commands+probe_image_commands+bv_test_copy_calls+bv_test_barrier_calls);
  d->CmdFillBuffer=fill;d->CmdCopyBuffer=copy;d->CmdPipelineBarrier=barrier;d->CmdClearColorImage=cc;d->CmdClearDepthStencilImage=cd;
  d->CmdCopyBufferToImage=up;d->CmdCopyImageToBuffer=down;d->EndCommandBuffer=end;
}
static void probe_rendering(Env e,BvRow* owner,BvRow* framebuffer) {
  unsigned rows=probe_rows(),allocations=bv_test_live_allocations;BvDevice* d=owner->context;
  PFN_vkCreateRenderPass cp=d->CreateRenderPass;PFN_vkDestroyRenderPass dp=d->DestroyRenderPass;
  PFN_vkCreateFramebuffer cf=d->CreateFramebuffer;PFN_vkDestroyFramebuffer df=d->DestroyFramebuffer;
  PFN_vkCmdBeginRenderPass begin=d->CmdBeginRenderPass;PFN_vkCmdEndRenderPass end=d->CmdEndRenderPass;
  d->CreateRenderPass=probe_create_pass;d->DestroyRenderPass=probe_destroy_pass;d->CreateFramebuffer=probe_create_fb;d->DestroyFramebuffer=probe_destroy_fb;
  d->CmdBeginRenderPass=probe_begin_pass;d->CmdEndRenderPass=probe_end_pass;
  for(unsigned fail=1;fail<=2;fail++) {
    unsigned calls=probe_pass_creates,destroyed=probe_pass_destroys;bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    bv_test_result(e,bv_create_render_pass(e,(Term[]){bv_test_handle(owner),probe_pass_info(e)},NULL),BV_LIMIT);
    assert(probe_pass_creates==calls+(fail==2) && probe_pass_destroys==destroyed+(fail==2));assert(bv_test_live_allocations==allocations);
  }
  bv_test_alloc_fail=0;
  for(unsigned fail=1;fail<=2;fail++) {
    unsigned calls=probe_pass_creates;bv_test_realloc_at=0;bv_test_realloc_fail=fail;
    bv_test_result(e,bv_create_render_pass(e,(Term[]){bv_test_handle(owner),probe_pass_info(e)},NULL),BV_LIMIT);assert(probe_pass_creates==calls && bv_test_live_allocations==allocations);
  }
  bv_test_realloc_fail=0;probe_render_result=VK_ERROR_OUT_OF_DEVICE_MEMORY;
  bv_test_result(e,bv_create_render_pass(e,(Term[]){bv_test_handle(owner),probe_pass_info(e)},NULL),(uint32_t)probe_render_result);assert(bv_test_live_allocations==allocations);
  probe_render_result=VK_SUCCESS;
  for(unsigned fail=1;fail<=6;fail++) {
    unsigned calls=probe_fb_creates,destroyed=probe_fb_destroys;bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    bv_test_result(e,bv_create_framebuffer(e,(Term[]){bv_test_handle(owner),probe_fb_info(e,framebuffer)},NULL),BV_LIMIT);
    assert(probe_fb_creates==calls+(fail==6) && probe_fb_destroys==destroyed+(fail==6) && probe_rows()==rows && bv_test_live_allocations==allocations);
  }
  bv_test_alloc_fail=0;probe_render_result=VK_ERROR_OUT_OF_HOST_MEMORY;
  bv_test_result(e,bv_create_framebuffer(e,(Term[]){bv_test_handle(owner),probe_fb_info(e,framebuffer)},NULL),(uint32_t)probe_render_result);probe_render_result=VK_SUCCESS;
  assert(bv_test_live_allocations==allocations);
  BvRow* pool=bv_test_pool(e,owner),*command=bv_test_command(e,owner,pool);bv_test_one(e,bv_begin_command_buffer,command,0);
  for(unsigned fail=1;fail<=2;fail++) {
    bv_test_alloc_at=0;bv_test_alloc_fail=fail;unsigned calls=probe_begins;
    bv_test_result(e,probe_begin_call(e,command,framebuffer),BV_LIMIT);
    assert(probe_begins==calls && !command->deps && bv_outside(command));
  }
  bv_test_alloc_fail=0;bv_test_result(e,probe_begin_call(e,command,framebuffer),0);
  BvDep* refs=command->deps;assert(refs && refs->target==framebuffer && refs->role==BV_DEP_RECORDED && !refs->next);
  assert(command->command.submission.recording.scope.tag==BV_INSIDE && command->command.submission.recording.scope.data.inside.framebuffer==framebuffer);
  probe_outside_guards(e,command,framebuffer);
  unsigned calls=probe_begins;bv_test_result(e,probe_begin_call(e,command,framebuffer),BV_LIFETIME);assert(probe_begins==calls && command->deps==refs);
  bv_test_one(e,bv_end_command_buffer,command,BV_LIFETIME);
  bv_test_alloc_at=0;bv_test_alloc_fail=1;bv_test_one(e,bv_cmd_end_render_pass,command,0);assert(!bv_test_alloc_at && bv_outside(command));bv_test_alloc_fail=0;
  bv_test_one(e,bv_cmd_end_render_pass,command,BV_LIFETIME);
  bv_test_one(e,bv_reset_command_buffer,command,0);bv_test_one(e,bv_begin_command_buffer,command,0);bv_test_result(e,probe_begin_call(e,command,framebuffer),0);
  refs=command->deps;PFN_vkResetCommandBuffer reset=d->ResetCommandBuffer;d->ResetCommandBuffer=bv_test_reset_error;
  bv_test_one(e,bv_reset_command_buffer,command,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);assert(command->command.phase==BV_COMMAND_INVALID && command->deps==refs && bv_referenced(framebuffer));
  probe_graph_retained(e,owner,framebuffer);
  d->ResetCommandBuffer=reset;bv_test_one(e,bv_reset_command_buffer,command,0);
  BvRow* image=bv_dependency(framebuffer->object.framebuffer.attachments[0]->target,BV_DEP_VIEW_IMAGE)->target;
  BvRow* memory=bv_bound_memory(image);uint32_t flags=memory->flags;memory->flags|=VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
  PFN_vkMapMemory map=d->MapMemory;PFN_vkUnmapMemory unmap=d->UnmapMemory;d->MapMemory=probe_graph_map;d->UnmapMemory=probe_graph_unmap;
  PFN_vkQueueSubmit submit=d->QueueSubmit;PFN_vkWaitForFences wait=d->WaitForFences;PFN_vkGetFenceStatus status=d->GetFenceStatus;PFN_vkDeviceWaitIdle idle=d->DeviceWaitIdle;
  d->QueueSubmit=bv_test_submit;d->WaitForFences=bv_test_wait;BvRow* fence=bv_test_fence(e,owner);
  for(unsigned uncertain=0;uncertain<2;uncertain++) {
    bv_test_one(e,bv_begin_command_buffer,command,0);bv_test_result(e,probe_begin_call(e,command,framebuffer),0);bv_test_one(e,bv_cmd_end_render_pass,command,0);bv_test_one(e,bv_end_command_buffer,command,0);
    assert(command->deps && command->deps->target==framebuffer && !command->deps->next);
    bv_test_submit_result=uncertain ? VK_ERROR_UNKNOWN : VK_SUCCESS;bv_test_submit_call(e,owner,command,fence,uncertain ? (uint32_t)VK_ERROR_UNKNOWN : 0);
    refs=command->deps;assert(bv_memory_busy(memory));unsigned maps=probe_maps;
    bv_test_one(e,bv_reset_command_buffer,command,BV_LIFETIME);bv_test_one(e,bv_fence_reset,fence,BV_LIFETIME);
    bv_test_result(e,bv_destroy_command_pool(e,(Term[]){bv_test_handle(owner),bv_test_handle(pool)},NULL),BV_LIFETIME);
    probe_graph_host_blocked(e,owner,memory);probe_graph_retained(e,owner,framebuffer);
    if(!uncertain) {
      bv_test_wait_result=VK_TIMEOUT;bv_test_status(e,bv_fence_wait(e,(Term[]){bv_test_handle(fence),bv_words(e,0)},NULL),VK_TIMEOUT);assert(bv_memory_busy(memory));
      probe_graph_host_blocked(e,owner,memory);
      d->GetFenceStatus=probe_status_not_ready;bv_test_status(e,bv_fence_status(e,(Term[]){bv_test_handle(fence)},NULL),VK_NOT_READY);d->GetFenceStatus=status;
      probe_graph_host_blocked(e,owner,memory);
      bv_test_wait_result=VK_SUCCESS;bv_test_status(e,bv_fence_wait(e,(Term[]){bv_test_handle(fence),bv_words(e,UINT64_MAX)},NULL),0);assert(command->command.phase==BV_COMPLETED);
    } else {
      bv_test_one(e,bv_fence_status,fence,BV_LIFETIME);d->DeviceWaitIdle=bv_test_idle_error;bv_test_idle_result=VK_ERROR_OUT_OF_HOST_MEMORY;
      bv_test_one(e,bv_device_wait_idle,owner,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);assert(bv_memory_busy(memory));probe_graph_host_blocked(e,owner,memory);
      d->DeviceWaitIdle=idle;bv_test_one(e,bv_device_wait_idle,owner,0);assert(command->command.phase==BV_COMMAND_INVALID);
    }
    assert(!bv_memory_busy(memory) && command->deps==refs && bv_referenced(framebuffer));
    Term byte[2];bv_unpack(e,bv_test_value(e,bv_read_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(memory),bv_words(e,0),1},NULL)),2,byte);
    assert(byte[0]==90 && term_aux(byte[1])==CID(Nil) && probe_maps==maps+1);
    probe_graph_retained(e,owner,framebuffer);
    d->ResetCommandBuffer=bv_test_reset_error;
    bv_test_one(e,bv_reset_command_buffer,command,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);assert(command->deps==refs);
    probe_graph_retained(e,owner,framebuffer);d->ResetCommandBuffer=reset;
    bv_test_one(e,bv_reset_command_buffer,command,0);assert(!command->deps);
  }
  memory->flags=flags;d->MapMemory=map;d->UnmapMemory=unmap;d->QueueSubmit=submit;d->WaitForFences=wait;d->GetFenceStatus=status;d->DeviceWaitIdle=idle;
  bv_test_result(e,bv_destroy_command_pool(e,(Term[]){bv_test_handle(owner),bv_test_handle(pool)},NULL),0);
  bv_test_result(e,bv_destroy_fence(e,(Term[]){bv_test_handle(owner),bv_test_handle(fence)},NULL),0);
  d->CreateRenderPass=cp;d->DestroyRenderPass=dp;d->CreateFramebuffer=cf;d->DestroyFramebuffer=df;d->CmdBeginRenderPass=begin;d->CmdEndRenderPass=end;
  assert(probe_rows()==rows && bv_test_live_allocations==allocations);
  puts("Controlled pass/framebuffer allocation rollback, fixed layouts, scope, framebuffer-only timeout/uncertainty and metadata cleanup passed");
}
static Term test_begin_render_pass(Env e,Term* f,IoWork* w) {
  static int ran;
  if(!ran) {
    BvRow* c=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_COMMAND),*fb=bv_get(bv_key(e,term_keep(e,f[1],1)),BV_FRAMEBUFFER);
    if(c && fb && fb->parent==bv_command_device(c)) {ran=1;probe_rendering(e,bv_command_device(c),fb);}
  }
  return bv_cmd_begin_render_pass(e,f,w);
}
static void probe_add_cleanup_graph(Env e,BvRow* owner,BvRow* command) {
  BvDevice* d=owner->context;
  BvRow* image=bv_get(bv_key(e,bv_test_value(e,bv_create_image(e,(Term[]){bv_test_handle(owner),probe_image_info(e)},NULL))),BV_IMAGE);assert(image);
  uint32_t type=0;while(type<d->memory.memoryTypeCount && !(image->requirements.memoryTypeBits&(1u<<type)))type++;
  assert(type<d->memory.memoryTypeCount);
  BvRow* memory=bv_get(bv_key(e,bv_test_value(e,bv_allocate_memory(e,(Term[]){bv_test_handle(owner),bv_words(e,image->requirements.size),type},NULL))),BV_MEMORY);
  bv_test_result(e,bv_bind_image_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(image),bv_test_handle(memory),bv_words(e,0)},NULL),0);
  BvRow* view=bv_get(bv_key(e,bv_test_value(e,bv_create_image_view(e,(Term[]){bv_test_handle(owner),probe_view_info(e,image)},NULL))),BV_IMAGE_VIEW);
  Term schema=io_node(e,CID(Con),bv_node(e,CID(AttachmentInfo),3,(Term[]){37,1,0}),term_pak(CID(Nil),0));
  BvRow* pass=bv_get(bv_key(e,bv_test_value(e,bv_create_render_pass(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(RenderPassCreateInfo),5,(Term[]){schema,0,0,0,0})},NULL))),BV_RENDER_PASS);
  Term views=io_node(e,CID(Con),bv_test_handle(view),term_pak(CID(Nil),0));
  BvRow* fb=bv_get(bv_key(e,bv_test_value(e,bv_create_framebuffer(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(FramebufferCreateInfo),4,(Term[]){pass->id,views,8,4})},NULL))),BV_FRAMEBUFFER);
  bv_test_one(e,bv_begin_command_buffer,command,0);
  Term barriers=io_node(e,CID(Con),bv_node(e,CID(ImageMemoryBarrier),10,(Term[]){image->id,1,0,1,0,1,0,2,0,256}),term_pak(CID(Nil),0));
  bv_test_result(e,bv_cmd_pipeline_barrier(e,(Term[]){bv_test_handle(command),1,1024,term_pak(CID(Nil),0),term_pak(CID(Nil),0),barriers},NULL),0);
  Term clear=io_node(e,CID(Con),bv_node(e,CID(ColorClear),4,(Term[]){0,0,f32_rewrap(1),f32_rewrap(1)}),term_pak(CID(Nil),0));
  bv_test_result(e,bv_cmd_begin_render_pass(e,(Term[]){bv_test_handle(command),bv_test_handle(fb),bv_node(e,CID(RenderArea),4,(Term[]){0,0,8,4}),clear},NULL),0);
  bv_test_one(e,bv_cmd_end_render_pass,command,0);bv_test_one(e,bv_end_command_buffer,command,0);
  assert(bv_referenced(image) && bv_referenced(view) && bv_referenced(pass) && bv_referenced(memory) && bv_referenced(fb));
}
static Term test_live_objects(Env e,Term* f,IoWork* w) {
  if(!bv_rows) assert(!bv_test_live_allocations);
  return bv_live_objects(e,f,w);
}
