#include <assert.h>

static void* bv_test_pointers[8192];
static unsigned bv_test_live_allocations;
static void bv_test_track(void* pointer) {
  if (!pointer) return;
  for (unsigned j=0;j<8192;j++) if (!bv_test_pointers[j]) {bv_test_pointers[j]=pointer;bv_test_live_allocations++;return;}
  abort();
}
static void bv_test_free(void* pointer) {
  for (unsigned j=0;j<8192;j++) if (pointer && bv_test_pointers[j]==pointer) {bv_test_pointers[j]=NULL;bv_test_live_allocations--;break;}
  free(pointer);
}
static unsigned bv_test_alloc_at, bv_test_alloc_fail;
static void* bv_test_alloc(size_t size) {
  if (++bv_test_alloc_at==bv_test_alloc_fail) return NULL;
  void* pointer=malloc(size);bv_test_track(pointer);return pointer;
}
static void* bv_test_calloc(size_t count,size_t size) {
  void* result=bv_test_alloc(count*size);if(result)memset(result,0,count*size);return result;
}
static unsigned bv_test_realloc_at,bv_test_realloc_fail;
static void* bv_test_realloc(void* pointer,size_t size) {
  if (++bv_test_realloc_at==bv_test_realloc_fail) return NULL;
  unsigned index=8192;
  for (unsigned j=0;j<8192;j++) if (pointer && bv_test_pointers[j]==pointer) {index=j;break;}
  void* result=realloc(pointer,size);
  if (result) {if (index<8192) bv_test_pointers[index]=result;else bv_test_track(result);}
  return result;
}
static unsigned bv_test_barrier_calls;
static VKAPI_ATTR void VKAPI_CALL bv_test_barrier(VkCommandBuffer c,VkPipelineStageFlags a,VkPipelineStageFlags b,VkDependencyFlags f,uint32_t nm,const VkMemoryBarrier* m,uint32_t nb,const VkBufferMemoryBarrier* buffers,uint32_t ni,const VkImageMemoryBarrier* images) {
  bv_test_barrier_calls++;
}
static unsigned bv_test_copy_calls;
static VKAPI_ATTR void VKAPI_CALL bv_test_copy(VkCommandBuffer c,VkBuffer a,VkBuffer b,uint32_t n,const VkBufferCopy* r) {
  bv_test_copy_calls++;
}
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_map_error(VkDevice d,VkDeviceMemory m,VkDeviceSize o,VkDeviceSize n,VkMemoryMapFlags f,void** p) {
  return VK_ERROR_MEMORY_MAP_FAILED;
}
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_flush_error(VkDevice d,uint32_t n,const VkMappedMemoryRange* r) {
  return VK_ERROR_OUT_OF_HOST_MEMORY;
}
static void bv_test_result(Env e,Term result,uint32_t expected) {
  if (!expected) { assert(term_aux(result)==CID(Done)); term_sink(e,result); return; }
  assert(term_aux(result)==CID(Fail));
  Term error[1],pair[2];bv_unpack(e,result,1,error);bv_unpack(e,error[0],2,pair);
  if ((uint32_t)pair[0]!=expected) {
    uint64_t length=0;char* message=io_cstr(e,pair[1],&length);
    fprintf(stderr,"Expected result %u, received %u: %s\n",expected,(uint32_t)pair[0],message);free(message);abort();
  }
  term_sink(e,pair[1]);
}
static Term bv_test_regions(Env e,uint64_t a,uint64_t b,uint64_t n) {
  Term fields[]={(uint32_t)a,(uint32_t)(a>>32),(uint32_t)b,(uint32_t)(b>>32),(uint32_t)n,(uint32_t)(n>>32)};
  return io_node(e,CID(Con),bv_node(e,CID(BufferCopy),6,fields),term_pak(CID(Nil),0));
}
static void bv_test_upload_result(Env e,BvRow* owner,BvRow* memory,bool terms,uint32_t expected) {
  Term values[]={16909060,134678021,202050057,269422093};
  Term array=term_keep(e,blk_new(e,terms,0,2,4,values),1);
  Term args[]={term_pak(CID(Device),owner->id),term_pak(CID(DeviceMemory),memory->id),bv_words(e,0),bv_words(e,3),bv_words(e,7),array};
  Term returned=bv_write_memory_words(e,args,NULL),pair[2];bv_unpack(e,returned,2,pair);
  assert(pair[0]==array);
  for (uint32_t j=0;j<4;j++) assert(blk_read(e.mem,terms,blk_loc(e.mem,pair[0]),j)==values[j]);
  bv_test_result(e,pair[1],expected);term_sink(e,pair[0]);term_sink(e,array);
}
static void bv_test_unit2(Env e,BvRow* command,BvRow* src,BvRow* dst) {
  BvRow* owner=bv_command_device(command);BvDevice* device=owner->context;
  PFN_vkCmdCopyBuffer copy=device->CmdCopyBuffer;device->CmdCopyBuffer=bv_test_copy;
  BvDep* before=command->deps;
  for (unsigned fail=1;fail<=2;fail++) {
    bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    Term args[]={term_pak(CID(CommandBuffer),command->id),term_pak(CID(Buffer),src->id),term_pak(CID(Buffer),dst->id),bv_test_regions(e,0,0,1)};
    bv_test_result(e,bv_cmd_copy_buffer(e,args,NULL),BV_LIMIT);
    assert(command->deps==before && bv_test_copy_calls==0);
  }
  bv_test_alloc_fail=0;bv_test_realloc_at=0;bv_test_realloc_fail=1;
  Term copy_oom[]={term_pak(CID(CommandBuffer),command->id),term_pak(CID(Buffer),src->id),term_pak(CID(Buffer),dst->id),bv_test_regions(e,0,0,1)};
  bv_test_result(e,bv_cmd_copy_buffer(e,copy_oom,NULL),BV_LIMIT);
  assert(command->deps==before && bv_test_copy_calls==0);bv_test_realloc_fail=0;
  PFN_vkCmdPipelineBarrier barrier=device->CmdPipelineBarrier;device->CmdPipelineBarrier=bv_test_barrier;
  for (unsigned fail=1;fail<=3;fail++) {
    bv_test_realloc_at=0;bv_test_realloc_fail=fail;
    Term mf[]={VK_ACCESS_TRANSFER_WRITE_BIT,VK_ACCESS_TRANSFER_READ_BIT};
    Term bf[]={src->id,0,0,1,0,VK_ACCESS_TRANSFER_WRITE_BIT,VK_ACCESS_TRANSFER_READ_BIT};
    Term args[]={term_pak(CID(CommandBuffer),command->id),VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,
      io_node(e,CID(Con),bv_node(e,CID(MemoryBarrier),2,mf),term_pak(CID(Nil),0)),
      io_node(e,CID(Con),bv_node(e,CID(BufferMemoryBarrier),7,bf),term_pak(CID(Nil),0)),term_pak(CID(Nil),0)};
    bv_test_result(e,bv_cmd_pipeline_barrier(e,args,NULL),BV_LIMIT);
    assert(command->deps==before && bv_test_barrier_calls==0);
  }
  bv_test_realloc_fail=0;device->CmdPipelineBarrier=barrier;device->CmdCopyBuffer=copy;
  PFN_vkMapMemory map=device->MapMemory;PFN_vkFlushMappedMemoryRanges flush=device->FlushMappedMemoryRanges;
  uint8_t saved[64];void* mapped=NULL;
  assert(bv_map(owner,bv_bound_memory(src),&mapped)==VK_SUCCESS);memcpy(saved,mapped,sizeof(saved));
  device->UnmapMemory(device->handle,(VkDeviceMemory)(uintptr_t)bv_bound_memory(src)->handle);
  device->MapMemory=bv_test_map_error;
  bv_test_upload_result(e,owner,bv_bound_memory(src),false,(uint32_t)VK_ERROR_MEMORY_MAP_FAILED);
  bv_test_upload_result(e,owner,bv_bound_memory(src),true,(uint32_t)VK_ERROR_MEMORY_MAP_FAILED);
  device->MapMemory=map;device->FlushMappedMemoryRanges=bv_test_flush_error;
  uint32_t flags=bv_bound_memory(src)->flags;bv_bound_memory(src)->flags &= ~VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
  bv_test_upload_result(e,owner,bv_bound_memory(src),false,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
  bv_bound_memory(src)->flags=flags;device->FlushMappedMemoryRanges=flush;
  bv_test_upload_result(e,owner,bv_bound_memory(src),true,0);
  assert(bv_map(owner,bv_bound_memory(src),&mapped)==VK_SUCCESS);
  assert(memcmp(mapped,(uint8_t[]){1,5,6,7,8,9,10},7)==0);memcpy(mapped,saved,sizeof(saved));
  if (!(flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
    VkMappedMemoryRange range={.sType=VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,.memory=(VkDeviceMemory)(uintptr_t)bv_bound_memory(src)->handle,.size=VK_WHOLE_SIZE};
    assert(flush(device->handle,1,&range)==VK_SUCCESS);
  }
  device->UnmapMemory(device->handle,(VkDeviceMemory)(uintptr_t)bv_bound_memory(src)->handle);
  puts("Injected metadata/map/flush checks and packed/Term array ownership passed");
}
/* CAPABILITY PROBES */
static void probe_add_cleanup_graph(Env e,BvRow* device,BvRow* command);
/* LIFECYCLE PROBES */
static Term bv_test_copy_buffer(Env e,Term* f,IoWork* w) {
  static int ran;
  if (!ran) {
    ran=1;BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);BvRow* src=bv_get(bv_key(e,f[1]),BV_BUFFER);
    BvRow* dst=NULL;
    for (BvRow* r=bv_rows;r;r=r->next)
      if (r->kind==BV_BUFFER && r->parent==src->parent && bv_bound_memory(r) && bv_bound_memory(r)!=bv_bound_memory(src)) {dst=r;break;}
    assert(dst);bv_test_unit2(e,command,src,dst);bv_test_capabilities(e,src->parent);bv_test_unit3(e,command,src,dst);
  }
  return bv_cmd_copy_buffer(e,f,w);
}
