static unsigned image_creates,image_destroys,view_creates,view_destroys,image_binds;
static VkResult image_result=VK_SUCCESS,view_result=VK_SUCCESS,bind_result=VK_SUCCESS,query_result=VK_SUCCESS;
static VKAPI_ATTR VkResult VKAPI_CALL probe_image_query(VkPhysicalDevice p,VkFormat f,VkImageType t,VkImageTiling tiling,VkImageUsageFlags u,VkImageCreateFlags flags,VkImageFormatProperties* out) {
  memset(out,0xff,sizeof(*out));
  if (query_result!=VK_SUCCESS) return query_result;
  *out=(VkImageFormatProperties){{4096,4096,1},13,256,1,UINT64_C(0x123456789abcdef0)};return VK_SUCCESS;
}
static VKAPI_ATTR VkResult VKAPI_CALL probe_create_image(VkDevice d,const VkImageCreateInfo* p,const VkAllocationCallbacks* a,VkImage* out) {
  image_creates++;assert(p->sType==VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO && !p->pNext && !a && !p->flags);
  assert(p->imageType==VK_IMAGE_TYPE_2D && p->extent.width==8 && p->extent.height==4 && p->extent.depth==1);
  assert(p->mipLevels==1 && p->arrayLayers==1 && p->samples==1 && p->tiling==0 && p->sharingMode==0 && p->initialLayout==0);
  *out=(VkImage)(uintptr_t)0xabc;return image_result;
}
static VKAPI_ATTR void VKAPI_CALL probe_image_requirements(VkDevice d,VkImage i,VkMemoryRequirements* r) { *r=(VkMemoryRequirements){256,64,1}; }
static VKAPI_ATTR void VKAPI_CALL probe_destroy_image(VkDevice d,VkImage i,const VkAllocationCallbacks* a) { image_destroys++; }
static VKAPI_ATTR VkResult VKAPI_CALL probe_bind_image(VkDevice d,VkImage i,VkDeviceMemory m,VkDeviceSize o) {image_binds++;return bind_result;}
static VKAPI_ATTR VkResult VKAPI_CALL probe_create_view(VkDevice d,const VkImageViewCreateInfo* p,const VkAllocationCallbacks* a,VkImageView* out) {
  view_creates++;assert(p->sType==VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO && !p->pNext && !a && !p->flags);
  assert(p->viewType==VK_IMAGE_VIEW_TYPE_2D && p->format==37 && p->subresourceRange.aspectMask==1 && p->subresourceRange.levelCount==1 && p->subresourceRange.layerCount==1);
  assert(!p->components.r && !p->components.g && !p->components.b && !p->components.a);
  *out=(VkImageView)(uintptr_t)0xdef;return view_result;
}
static VKAPI_ATTR void VKAPI_CALL probe_destroy_view(VkDevice d,VkImageView i,const VkAllocationCallbacks* a) {view_destroys++;}
static Term probe_image_info(Env e) {return bv_node(e,CID(ImageCreateInfo),6,(Term[]){37,8,4,1,1,23});}
static Term probe_view_info(Env e,BvRow* image) {return bv_node(e,CID(ImageViewCreateInfo),7,(Term[]){image->id,1,1,0,1,0,1});}
static unsigned probe_rows(void) {unsigned n=0;for(BvRow* r=bv_rows;r;r=r->next)n++;return n;}
static void probe_binding_policy(BvRow* owner) {
  BvDevice* d=owner->context;uint64_t g=d->limits.bufferImageGranularity;d->limits.bufferImageGranularity=256;
  BvRow memory={.parent=owner,.kind=BV_MEMORY,.size=UINT64_MAX,.memory_type=0};
  BvRow a={.parent=owner,.kind=BV_IMAGE,.requirements={128,64,1}},b={.parent=owner,.kind=BV_BUFFER,.requirements={128,64,1}};
  BvDep edge={.target=&memory,.role=BV_DEP_BINDING,.offset=0};a.deps=&edge;
  BvRow* saved=bv_rows;a.next=bv_rows;bv_rows=&a;
  assert(bv_binding_check(&b,&memory,64)==BV_ARGUMENT);
  assert(bv_binding_check(&b,&memory,128)==BV_ARGUMENT);
  assert(bv_binding_check(&b,&memory,256)==0);
  assert(bv_binding_check(&b,&memory,UINT64_MAX-63)==BV_ARGUMENT);
  assert(bv_binding_check(&b,&memory,UINT64_C(0x100000000))==0);
  a.kind=BV_BUFFER;b.kind=BV_IMAGE;
  assert(bv_binding_check(&b,&memory,64)==BV_ARGUMENT && bv_binding_check(&b,&memory,128)==BV_ARGUMENT && bv_binding_check(&b,&memory,256)==0);
  a.kind=BV_IMAGE;assert(bv_binding_check(&b,&memory,128)==0);
  a.kind=BV_BUFFER;b.kind=BV_BUFFER;assert(bv_binding_check(&b,&memory,0)==0);
  bv_rows=saved;d->limits.bufferImageGranularity=g;
}
static void probe_image_resources(Env e,BvRow* owner) {
  unsigned before=probe_rows();BvDevice* d=owner->context;BvInstance* i=owner->parent->context;
  PFN_vkCreateImage create=d->CreateImage;PFN_vkDestroyImage destroy=d->DestroyImage;PFN_vkGetImageMemoryRequirements req=d->GetImageMemoryRequirements;
  PFN_vkBindImageMemory bind=d->BindImageMemory;PFN_vkCreateImageView view=d->CreateImageView;PFN_vkDestroyImageView dv=d->DestroyImageView;
  PFN_vkGetPhysicalDeviceImageFormatProperties query=i->image_formats;
  d->CreateImage=probe_create_image;d->DestroyImage=probe_destroy_image;d->GetImageMemoryRequirements=probe_image_requirements;
  d->BindImageMemory=probe_bind_image;d->CreateImageView=probe_create_view;d->DestroyImageView=probe_destroy_view;i->image_formats=probe_image_query;
  BvRow* physical=NULL;for(BvRow* r=bv_rows;r;r=r->next)if(r->kind==BV_PHYSICAL && r->handle==(uint64_t)(uintptr_t)d->physical && r->parent==owner->parent)physical=r;
  assert(physical);
  for(unsigned mode=0;mode<2;mode++) {
    query_result=mode ? VK_ERROR_FORMAT_NOT_SUPPORTED : VK_SUCCESS;
    Term args[]={bv_test_handle(owner->parent),bv_test_handle(physical),bv_node(e,CID(ImageFormatInfo),5,(Term[]){37,1,0,23,0})};
    Term result=bv_image_format_properties(e,args,NULL);
    if(mode) bv_test_result(e,result,(uint32_t)VK_ERROR_FORMAT_NOT_SUPPORTED);
    else {Term pairs[2],tail[2],last[2];bv_unpack(e,bv_test_value(e,result),2,pairs);term_sink(e,pairs[0]);bv_unpack(e,pairs[1],2,tail);term_sink(e,tail[0]);bv_unpack(e,tail[1],2,last);term_sink(e,last[0]);assert(bv_u64(e,last[1])==UINT64_C(0x123456789abcdef0));}
  }
  query_result=VK_SUCCESS;
  image_result=VK_ERROR_OUT_OF_DEVICE_MEMORY;
  bv_test_result(e,bv_create_image(e,(Term[]){bv_test_handle(owner),probe_image_info(e)},NULL),(uint32_t)image_result);assert(image_destroys==0);
  image_result=VK_SUCCESS;bv_test_alloc_at=0;bv_test_alloc_fail=1;
  bv_test_result(e,bv_create_image(e,(Term[]){bv_test_handle(owner),probe_image_info(e)},NULL),BV_LIMIT);assert(image_destroys==1);bv_test_alloc_fail=0;
  BvRow* image=bv_get(bv_key(e,bv_test_value(e,bv_create_image(e,(Term[]){bv_test_handle(owner),probe_image_info(e)},NULL))),BV_IMAGE);assert(image);
  BvRow* memory=bv_add(BV_MEMORY,owner);assert(memory);memory->size=4096;
  bv_test_alloc_at=0;bv_test_alloc_fail=1;
  bv_test_result(e,bv_bind_image_memory(e,(Term[]){bv_test_handle(owner),term_pak(CID(ImageHandle),image->id),bv_test_handle(memory),bv_words(e,0)},NULL),BV_LIMIT);assert(!image_binds && !image->deps);bv_test_alloc_fail=0;
  bind_result=VK_ERROR_OUT_OF_DEVICE_MEMORY;
  bv_test_result(e,bv_bind_image_memory(e,(Term[]){bv_test_handle(owner),term_pak(CID(ImageHandle),image->id),bv_test_handle(memory),bv_words(e,0)},NULL),(uint32_t)bind_result);assert(!image->deps);
  bind_result=VK_SUCCESS;bv_test_result(e,bv_bind_image_memory(e,(Term[]){bv_test_handle(owner),term_pak(CID(ImageHandle),image->id),bv_test_handle(memory),bv_words(e,0)},NULL),0);
  for(unsigned fail=1;fail<=2;fail++) {
    unsigned calls=view_creates,destroyed=view_destroys;bv_test_alloc_at=0;bv_test_alloc_fail=fail;
    bv_test_result(e,bv_create_image_view(e,(Term[]){bv_test_handle(owner),probe_view_info(e,image)},NULL),BV_LIMIT);
    assert(view_creates==calls+(fail==2) && view_destroys==destroyed+(fail==2));
  }
  bv_test_alloc_fail=0;view_result=VK_ERROR_OUT_OF_HOST_MEMORY;
  bv_test_result(e,bv_create_image_view(e,(Term[]){bv_test_handle(owner),probe_view_info(e,image)},NULL),(uint32_t)view_result);view_result=VK_SUCCESS;
  BvRow* v=bv_get(bv_key(e,bv_test_value(e,bv_create_image_view(e,(Term[]){bv_test_handle(owner),probe_view_info(e,image)},NULL))),BV_IMAGE_VIEW);assert(v);
  bv_test_result(e,bv_destroy_image(e,(Term[]){bv_test_handle(owner),term_pak(CID(ImageHandle),image->id)},NULL),BV_LIFETIME);
  bv_test_result(e,bv_destroy_image_view(e,(Term[]){bv_test_handle(owner),term_pak(CID(ImageView),v->id)},NULL),0);
  bv_test_result(e,bv_destroy_image(e,(Term[]){bv_test_handle(owner),term_pak(CID(ImageHandle),image->id)},NULL),0);bv_remove(memory);
  probe_binding_policy(owner);assert(probe_rows()==before);
  d->CreateImage=create;d->DestroyImage=destroy;d->GetImageMemoryRequirements=req;d->BindImageMemory=bind;d->CreateImageView=view;d->DestroyImageView=dv;i->image_formats=query;
  puts("Controlled image query/create/bind/view rollback, exact high limbs, both binding orders and zero-row delta passed");
}
static Term test_destroy_image_view(Env e,Term* f,IoWork* w) {
  static int ran;
  if(!ran) {ran=1;BvRow* owner=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_DEVICE);assert(owner);probe_image_resources(e,owner);}
  return bv_destroy_image_view(e,f,w);
}
