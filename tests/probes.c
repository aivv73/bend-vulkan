#include <assert.h>

static unsigned bv_test_alloc_at, bv_test_alloc_fail;
static void* bv_test_alloc(size_t size) {
  if (++bv_test_alloc_at==bv_test_alloc_fail) return NULL;
  return malloc(size);
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
  assert((uint32_t)pair[0]==expected);term_sink(e,pair[1]);
}
static Term bv_test_regions(Env e,uint64_t a,uint64_t b,uint64_t n) {
  Term fields[]={(uint32_t)a,(uint32_t)(a>>32),(uint32_t)b,(uint32_t)(b>>32),(uint32_t)n,(uint32_t)(n>>32)};
  return io_node(e,CID(Con),bv_node(e,CID(BufferCopy),6,fields),term_pak(CID(Nil),0));
}
static void bv_test_upload_result(Env e,BvRow* owner,BvRow* memory,bool terms,uint32_t expected) {
  Term values[]={16909060,134678021,202050057,269422093};
  Term array=blk_new(e,terms,0,2,4,values);
  Term args[]={term_pak(CID(Device),owner->id),term_pak(CID(DeviceMemory),memory->id),bv_words(e,0),bv_words(e,7),array};
  Term returned=bv_write_memory_words(e,args,NULL),pair[2];bv_unpack(e,returned,2,pair);
  assert(pair[0]==array);
  for (uint32_t j=0;j<4;j++) assert(blk_read(e.mem,terms,blk_loc(e.mem,pair[0]),j)==values[j]);
  bv_test_result(e,pair[1],expected);term_sink(e,pair[0]);
}
static void bv_test_unit2(Env e,BvRow* command,BvRow* src,BvRow* dst) {
  BvRow* owner=bv_command_device(command);BvDevice* device=owner->context;
  PFN_vkCmdCopyBuffer copy=device->CmdCopyBuffer;device->CmdCopyBuffer=bv_test_copy;
  BvUse* before=command->uses;
  for (unsigned fail=1;fail<=2;fail++) {
    bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    Term args[]={term_pak(CID(CommandBuffer),command->id),term_pak(CID(Buffer),src->id),term_pak(CID(Buffer),dst->id),bv_test_regions(e,0,0,1)};
    bv_test_result(e,bv_cmd_copy_buffer(e,args,NULL),BV_LIMIT);
    assert(command->uses==before && bv_test_copy_calls==0);
  }
  bv_test_alloc_fail=0;device->CmdCopyBuffer=copy;
  PFN_vkMapMemory map=device->MapMemory;PFN_vkFlushMappedMemoryRanges flush=device->FlushMappedMemoryRanges;
  uint8_t saved[64];void* mapped=NULL;
  assert(bv_map(owner,src->bound,&mapped)==VK_SUCCESS);memcpy(saved,mapped,sizeof(saved));
  device->UnmapMemory(device->handle,(VkDeviceMemory)(uintptr_t)src->bound->handle);
  device->MapMemory=bv_test_map_error;
  bv_test_upload_result(e,owner,src->bound,false,(uint32_t)VK_ERROR_MEMORY_MAP_FAILED);
  bv_test_upload_result(e,owner,src->bound,true,(uint32_t)VK_ERROR_MEMORY_MAP_FAILED);
  device->MapMemory=map;device->FlushMappedMemoryRanges=bv_test_flush_error;
  uint32_t flags=src->bound->flags;src->bound->flags &= ~VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
  bv_test_upload_result(e,owner,src->bound,false,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
  src->bound->flags=flags;device->FlushMappedMemoryRanges=flush;
  bv_test_upload_result(e,owner,src->bound,true,0);
  assert(bv_map(owner,src->bound,&mapped)==VK_SUCCESS);memcpy(mapped,saved,sizeof(saved));
  if (!(flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
    VkMappedMemoryRange range={.sType=VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,.memory=(VkDeviceMemory)(uintptr_t)src->bound->handle,.size=VK_WHOLE_SIZE};
    assert(flush(device->handle,1,&range)==VK_SUCCESS);
  }
  device->UnmapMemory(device->handle,(VkDeviceMemory)(uintptr_t)src->bound->handle);
  puts("Injected metadata/map/flush checks and packed/Term array ownership passed");
}
static Term bv_test_copy_buffer(Env e,Term* f,IoWork* w) {
  static int ran;
  if (!ran) {
    ran=1;BvRow* command=bv_get(bv_key(e,f[0]),BV_COMMAND);BvRow* src=bv_get(bv_key(e,f[1]),BV_BUFFER);
    BvRow* dst=NULL;
    for (BvRow* r=bv_rows;r;r=r->next)
      if (r->kind==BV_BUFFER && r->parent==src->parent && r->bound && r->bound!=src->bound) {dst=r;break;}
    assert(dst);bv_test_unit2(e,command,src,dst);
  }
  return bv_cmd_copy_buffer(e,f,w);
}
