static unsigned bv_test_enum_mode,bv_test_enum_calls;
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_layers(uint32_t* count,VkLayerProperties* data) {
  bv_test_enum_calls++;
  if (!data) { *count=bv_test_enum_mode==2 ? 5000 : bv_test_enum_mode==3 ? 0 : 1;return VK_SUCCESS; }
  assert(*count>=1);*count=1;memset(data,0,sizeof(*data));
  strcpy(data->layerName,"probe-layer");strcpy(data->description,"probe-description");data->specVersion=123;data->implementationVersion=456;
  return bv_test_enum_mode==1 ? VK_INCOMPLETE : VK_SUCCESS;
}
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_extensions(const char* layer,uint32_t* count,VkExtensionProperties* data) {
  assert(layer && strcmp(layer,"probe-layer")==0);
  if (!data) { *count=1;return VK_SUCCESS; }
  assert(*count>=1);*count=1;memset(data,0,sizeof(*data));strcpy(data->extensionName,"probe-extension");data->specVersion=789;return VK_SUCCESS;
}
static VKAPI_ATTR VkResult VKAPI_CALL bv_test_device_extensions(VkPhysicalDevice p,const char* layer,uint32_t* count,VkExtensionProperties* data) {
  return bv_test_extensions(layer,count,data);
}
static VKAPI_ATTR void VKAPI_CALL bv_test_heaps(VkPhysicalDevice p,VkPhysicalDeviceMemoryProperties* out) {
  memset(out,0,sizeof(*out));out->memoryHeapCount=1;out->memoryHeaps[0].size=UINT64_C(0x123456789abcdef);out->memoryHeaps[0].flags=1;
}
static VKAPI_ATTR void VKAPI_CALL bv_test_limits(VkPhysicalDevice p,VkPhysicalDeviceProperties* out) {
  memset(out,0,sizeof(*out));VkPhysicalDeviceLimits* v=&out->limits;
  v->maxImageDimension2D=1;v->maxFramebufferWidth=2;v->maxFramebufferHeight=3;v->maxColorAttachments=4;v->maxPushConstantsSize=5;
  v->maxVertexInputAttributes=6;v->maxVertexInputBindings=7;v->maxVertexInputAttributeOffset=8;v->maxVertexInputBindingStride=9;v->maxMemoryAllocationCount=10;
  v->nonCoherentAtomSize=UINT64_C(0x123456789abcdef);v->optimalBufferCopyOffsetAlignment=UINT64_C(0x23456789abcdef01);v->optimalBufferCopyRowPitchAlignment=UINT64_MAX;
}
static VKAPI_ATTR void VKAPI_CALL bv_test_formats(VkPhysicalDevice p,VkFormat format,VkFormatProperties* out) {
  assert(format==VK_FORMAT_R8G8B8A8_UNORM);out->linearTilingFeatures=11;out->optimalTilingFeatures=22;out->bufferFeatures=33;
}
static Term bv_test_query_value(Env e,Term result) {
  assert(term_aux(result)==CID(Done));Term fields[1];bv_unpack(e,result,1,fields);return fields[0];
}
static void bv_test_extension_result(Env e,Term result) {
  Term list=bv_test_query_value(e,result);assert(term_aux(list)==CID(Con));
  Term item[2],fields[2];bv_unpack(e,list,2,item);assert(term_aux(item[1])==CID(Nil));bv_unpack(e,item[0],2,fields);
  uint64_t length=0;char* name=io_cstr(e,fields[0],&length);assert(strcmp(name,"probe-extension")==0 && fields[1]==789);free(name);
}
static void bv_test_capabilities(Env e,BvRow* device_row) {
  BvRow* instance_row=device_row->parent;BvRow* entry_row=instance_row->parent;
  BvDevice* device=device_row->context;BvInstance* instance=instance_row->context;BvEntry* entry=entry_row->context;BvRow* physical=NULL;
  for (BvRow* r=bv_rows;r;r=r->next)
    if (r->kind==BV_PHYSICAL && r->parent==instance_row && r->handle==(uint64_t)(uintptr_t)device->physical) {physical=r;break;}
  assert(physical);
  PFN_vkEnumerateInstanceLayerProperties layers=entry->layers;entry->layers=bv_test_layers;
  Term args[]={term_pak(CID(Entry),entry_row->id)};
  bv_test_enum_mode=0;Term list=bv_test_query_value(e,bv_instance_layers(e,args,NULL));Term item[2],fields[4];
  assert(term_aux(list)==CID(Con));bv_unpack(e,list,2,item);assert(term_aux(item[1])==CID(Nil));bv_unpack(e,item[0],4,fields);
  uint64_t length=0;char* name=io_cstr(e,fields[0],&length);char* description=io_cstr(e,fields[3],&length);
  assert(strcmp(name,"probe-layer")==0 && strcmp(description,"probe-description")==0 && fields[1]==123 && fields[2]==456);free(name);free(description);
  bv_test_enum_mode=1;bv_test_enum_calls=0;bv_test_result(e,bv_instance_layers(e,args,NULL),VK_INCOMPLETE);assert(bv_test_enum_calls==16);
  bv_test_enum_mode=2;bv_test_enum_calls=0;bv_test_result(e,bv_instance_layers(e,args,NULL),BV_LIMIT);assert(bv_test_enum_calls==1);
  bv_test_enum_mode=3;assert(term_aux(bv_test_query_value(e,bv_instance_layers(e,args,NULL)))==CID(Nil));entry->layers=layers;
  PFN_vkEnumerateInstanceExtensionProperties extensions=entry->extensions;entry->extensions=bv_test_extensions;
  Term layer_fields[]={io_str(e,"probe-layer",11)};
  Term ext[]={term_pak(CID(Entry),entry_row->id),bv_node(e,CID(Some),1,layer_fields)};
  bv_test_extension_result(e,bv_instance_extensions(e,ext,NULL));entry->extensions=extensions;
  PFN_vkEnumerateDeviceExtensionProperties device_extensions=instance->extensions;instance->extensions=bv_test_device_extensions;
  Term device_layer[]={io_str(e,"probe-layer",11)};
  Term dext[]={term_pak(CID(Instance),instance_row->id),term_pak(CID(PhysicalDevice),physical->id),bv_node(e,CID(Some),1,device_layer)};
  bv_test_extension_result(e,bv_device_extensions(e,dext,NULL));instance->extensions=device_extensions;
  Term query[]={term_pak(CID(Instance),instance_row->id),term_pak(CID(PhysicalDevice),physical->id),VK_FORMAT_R8G8B8A8_UNORM};
  PFN_vkGetPhysicalDeviceMemoryProperties memory=instance->memory;instance->memory=bv_test_heaps;
  list=bv_test_query_value(e,bv_memory_heaps(e,query,NULL));assert(term_aux(list)==CID(Con));bv_unpack(e,list,2,item);
  Term heap[2];bv_unpack(e,item[0],2,heap);assert(bv_u64(e,heap[0])==UINT64_C(0x123456789abcdef) && heap[1]==1);term_sink(e,item[1]);instance->memory=memory;
  PFN_vkGetPhysicalDeviceProperties properties=instance->properties;instance->properties=bv_test_limits;
  Term tuple=bv_test_query_value(e,bv_physical_limits(e,query,NULL));
  for (uint32_t j=1;j<=10;j++) {Term pair[2];bv_unpack(e,tuple,2,pair);assert(pair[0]==j);tuple=pair[1];}
  Term pair[2];bv_unpack(e,tuple,2,pair);assert(bv_u64(e,pair[0])==UINT64_C(0x123456789abcdef));
  Term align[2];bv_unpack(e,pair[1],2,align);assert(bv_u64(e,align[0])==UINT64_C(0x23456789abcdef01) && bv_u64(e,align[1])==UINT64_MAX);instance->properties=properties;
  PFN_vkGetPhysicalDeviceFormatProperties formats=instance->formats;instance->formats=bv_test_formats;
  Term format[3];bv_unpack(e,bv_test_query_value(e,bv_format_properties(e,query,NULL)),3,format);
  assert(format[0]==11 && format[1]==22 && format[2]==33);instance->formats=formats;
  puts("Injected layer/extension dispatch, eight enumeration retries, count limits, and composite capability ABI passed");
}
