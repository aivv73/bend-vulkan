static unsigned probe_image_commands;
static VKAPI_ATTR void VKAPI_CALL probe_clear_color(VkCommandBuffer c,VkImage i,VkImageLayout layout,const VkClearColorValue* v,uint32_t n,const VkImageSubresourceRange* ranges) {
  probe_image_commands++;assert(layout==7 && n==1 && ranges[0].levelCount==1 && ranges[0].layerCount==2);
  assert(v->float32[0]==0.25f && v->float32[1]==-0.5f && v->float32[2]==1.0f && signbit(v->float32[3]));
}
static VKAPI_ATTR void VKAPI_CALL probe_clear_depth(VkCommandBuffer c,VkImage i,VkImageLayout layout,const VkClearDepthStencilValue* v,uint32_t n,const VkImageSubresourceRange* ranges) {
  uint32_t bits;memcpy(&bits,&v->depth,4);assert(bits==0x3f000000 && !v->stencil);probe_image_commands++;
}
static VKAPI_ATTR void VKAPI_CALL probe_copy_upload(VkCommandBuffer c,VkBuffer b,VkImage i,VkImageLayout layout,uint32_t n,const VkBufferImageCopy* regions) {
  assert(layout==7 && n==1);probe_image_commands++;
}
static VKAPI_ATTR void VKAPI_CALL probe_copy_download(VkCommandBuffer c,VkImage i,VkImageLayout layout,VkBuffer b,uint32_t n,const VkBufferImageCopy* regions) {
  assert(layout==6 && n==1);probe_image_commands++;
}
static VKAPI_ATTR void VKAPI_CALL probe_image_barrier(VkCommandBuffer c,VkPipelineStageFlags a,VkPipelineStageFlags b,VkDependencyFlags f,uint32_t nm,const VkMemoryBarrier* m,uint32_t nb,const VkBufferMemoryBarrier* buffers,uint32_t ni,const VkImageMemoryBarrier* images) {
  assert(ni==1 && !nm && !nb && !f);assert(images[0].sType==VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER && !images[0].pNext);
  assert(images[0].oldLayout==0 && images[0].newLayout==7 && !images[0].srcAccessMask && images[0].dstAccessMask==4096);
  assert(images[0].srcQueueFamilyIndex==VK_QUEUE_FAMILY_IGNORED && images[0].dstQueueFamilyIndex==VK_QUEUE_FAMILY_IGNORED);probe_image_commands++;
}
static Term probe_range_list(Env e,uint32_t aspect) {return io_node(e,CID(Con),bv_node(e,CID(ImageSubresourceRange),5,(Term[]){aspect,1,1,0,2}),term_pak(CID(Nil),0));}
static Term probe_color(Env e) {return bv_node(e,CID(ClearColor),4,(Term[]){f32_rewrap(0.25f),f32_rewrap(-0.5f),f32_rewrap(1.0f),f32_rewrap(-0.0f)});}
static Term probe_image_region(Env e,uint32_t aspect,uint32_t x,uint32_t y,uint32_t width,uint32_t height) {
  return io_node(e,CID(Con),bv_node(e,CID(BufferImageCopy),12,(Term[]){20,0,9,6,aspect,1,0,2,x,y,width,height}),term_pak(CID(Nil),0));
}
static Term probe_clear_call(Env e,BvRow* c,BvRow* i) {
  return bv_cmd_clear_color_image(e,(Term[]){bv_test_handle(c),bv_test_handle(i),7,probe_color(e),probe_range_list(e,1)},NULL);
}
static Term probe_transfer_call(Env e,BvRow* c,BvRow* i,BvRow* b,int upload,uint32_t aspect,uint32_t x,uint32_t y,uint32_t width,uint32_t height) {
  Term regions=probe_image_region(e,aspect,x,y,width,height);
  return upload ? bv_cmd_copy_buffer_to_image(e,(Term[]){bv_test_handle(c),bv_test_handle(b),bv_test_handle(i),7,regions},NULL) :
    bv_cmd_copy_image_to_buffer(e,(Term[]){bv_test_handle(c),bv_test_handle(i),6,bv_test_handle(b),regions},NULL);
}
static Term probe_barrier_call(Env e,BvRow* c,BvRow* i) {
  return bv_cmd_pipeline_barrier(e,(Term[]){bv_test_handle(c),1,4096,term_pak(CID(Nil),0),term_pak(CID(Nil),0),
    io_node(e,CID(Con),bv_node(e,CID(ImageMemoryBarrier),10,(Term[]){i->id,1,1,1,0,2,0,7,0,4096}),term_pak(CID(Nil),0))},NULL);
}
static void probe_image_transfers(Env e,BvRow* owner,BvRow* image) {
  unsigned before=probe_rows();uint64_t end;
  assert(bv_copy_end(12,7,5,3,2,2,4,&end) && end==192);
  assert(bv_copy_end(20,9,6,3,2,2,4,&end) && end==284);
  assert(!bv_copy_end(UINT64_MAX,0,0,1,1,1,4,&end));
  assert(!bv_copy_end(0,UINT32_MAX,UINT32_MAX,1,1,UINT32_MAX,4,&end));
  BvDevice* d=owner->context;BvRow* buffer=NULL;
  for(BvRow* r=bv_rows;r;r=r->next)if(r->kind==BV_BUFFER && r->parent==owner && r->size>=2048 && bv_bound_memory(r))buffer=r;
  assert(buffer);BvRow* pool=bv_test_pool(e,owner),*command=bv_test_command(e,owner,pool);bv_test_one(e,bv_begin_command_buffer,command,0);
  PFN_vkCmdClearColorImage cc=d->CmdClearColorImage;PFN_vkCmdClearDepthStencilImage cd=d->CmdClearDepthStencilImage;
  PFN_vkCmdCopyBufferToImage up=d->CmdCopyBufferToImage;PFN_vkCmdCopyImageToBuffer down=d->CmdCopyImageToBuffer;PFN_vkCmdPipelineBarrier barrier=d->CmdPipelineBarrier;
  d->CmdClearColorImage=probe_clear_color;d->CmdClearDepthStencilImage=probe_clear_depth;d->CmdCopyBufferToImage=probe_copy_upload;d->CmdCopyImageToBuffer=probe_copy_download;d->CmdPipelineBarrier=probe_image_barrier;
  for(unsigned operation=0;operation<4;operation++) {
    unsigned allocations=operation==1 || operation==2 ? 2 : 1;
    for(unsigned fail=1;fail<=allocations;fail++) {
      bv_test_alloc_at=0;bv_test_alloc_fail=fail;unsigned calls=probe_image_commands;
      Term result=operation==0 ? probe_clear_call(e,command,image) : operation==3 ? probe_barrier_call(e,command,image) : probe_transfer_call(e,command,image,buffer,operation==1,1,1,1,3,2);
      bv_test_result(e,result,BV_LIMIT);assert(!command->deps && probe_image_commands==calls);
    }
    bv_test_alloc_fail=0;
    for(unsigned fail=1;fail<=(operation==3 ? 2 : 1);fail++) {
      bv_test_realloc_at=0;bv_test_realloc_fail=fail;unsigned calls=probe_image_commands;
      Term result=operation==0 ? probe_clear_call(e,command,image) : operation==3 ? probe_barrier_call(e,command,image) : probe_transfer_call(e,command,image,buffer,operation==1,1,1,1,3,2);
      bv_test_result(e,result,BV_LIMIT);assert(!command->deps && probe_image_commands==calls);
    }
    bv_test_realloc_fail=0;
  }
  bv_test_result(e,probe_clear_call(e,command,image),0);BvDep* retained=command->deps;assert(retained && !retained->next);
  bv_test_realloc_at=0;bv_test_realloc_fail=1;bv_test_result(e,probe_transfer_call(e,command,image,buffer,1,1,1,1,3,2),BV_LIMIT);assert(command->deps==retained);bv_test_realloc_fail=0;
  bv_test_result(e,probe_transfer_call(e,command,image,buffer,1,1,1,1,3,2),0);
  bv_test_result(e,probe_transfer_call(e,command,image,buffer,0,1,1,1,3,2),0);
  bv_test_result(e,probe_barrier_call(e,command,image),0);
  unsigned calls=probe_image_commands;VkExtent3D granularity=d->queue_properties.minImageTransferGranularity;uint32_t flags=d->queue_flags;
  d->queue_properties.minImageTransferGranularity=(VkExtent3D){0,0,0};
  bv_test_result(e,probe_transfer_call(e,command,image,buffer,1,1,1,1,3,2),BV_ARGUMENT);assert(probe_image_commands==calls);
  bv_test_result(e,probe_transfer_call(e,command,image,buffer,1,1,0,0,5,3),0);
  d->queue_properties.minImageTransferGranularity=(VkExtent3D){4,2,1};
  bv_test_result(e,probe_transfer_call(e,command,image,buffer,1,1,1,0,3,2),BV_ARGUMENT);
  bv_test_result(e,probe_transfer_call(e,command,image,buffer,1,1,4,2,1,1),0);
  d->queue_properties.minImageTransferGranularity=(VkExtent3D){1,1,1};d->queue_flags=VK_QUEUE_TRANSFER_BIT;
  bv_test_result(e,probe_clear_call(e,command,image),BV_ARGUMENT);
  BvImage saved=image->object.image;image->object.image.format=VK_FORMAT_D32_SFLOAT;
  bv_test_result(e,probe_transfer_call(e,command,image,buffer,1,2,1,1,3,2),BV_ARGUMENT);
  bv_test_result(e,bv_cmd_clear_depth_image(e,(Term[]){bv_test_handle(command),bv_test_handle(image),7,f32_rewrap(0.5f),probe_range_list(e,2)},NULL),BV_ARGUMENT);
  d->queue_flags=flags;bv_test_result(e,bv_cmd_clear_depth_image(e,(Term[]){bv_test_handle(command),bv_test_handle(image),7,f32_rewrap(0.5f),probe_range_list(e,2)},NULL),0);
  image->object.image=saved;d->queue_properties.minImageTransferGranularity=granularity;
  calls=probe_image_commands;
  bv_test_result(e,bv_cmd_clear_color_image(e,(Term[]){bv_test_handle(command),bv_test_handle(image),7,
    bv_node(e,CID(ClearColor),4,(Term[]){f32_rewrap(NAN),0,0,0}),probe_range_list(e,1)},NULL),BV_ARGUMENT);assert(probe_image_commands==calls);
  bv_test_one(e,bv_reset_command_buffer,command,0);assert(!command->deps);
  d->CmdClearColorImage=cc;d->CmdClearDepthStencilImage=cd;d->CmdCopyBufferToImage=up;d->CmdCopyImageToBuffer=down;d->CmdPipelineBarrier=barrier;
  bv_test_result(e,bv_destroy_command_pool(e,(Term[]){bv_test_handle(owner),bv_test_handle(pool)},NULL),0);assert(probe_rows()==before);
  puts("Controlled image command F32, all preparation allocations, rollback, exact spans, queue granularity and depth restrictions passed");
}
static Term test_clear_color_image(Env e,Term* f,IoWork* w) {
  static int ran;
  if(!ran) {ran=1;BvRow* command=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_COMMAND),*image=bv_get(bv_key(e,term_keep(e,f[1],1)),BV_IMAGE);assert(command && image);probe_image_transfers(e,bv_command_device(command),image);}
  return bv_cmd_clear_color_image(e,f,w);
}
