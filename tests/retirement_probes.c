static BvRow* retirement_buffer(Env e,BvRow* owner) {
  BvRow* buffer=bv_get(bv_key(e,bv_test_value(e,bv_create_buffer(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(BufferCreateInfo),3,(Term[]){64,0,67})},NULL))),BV_BUFFER);
  uint32_t type=0;while(!(buffer->requirements.memoryTypeBits&(1u<<type)))type++;
  BvRow* memory=bv_get(bv_key(e,bv_test_value(e,bv_allocate_memory(e,(Term[]){bv_test_handle(owner),bv_words(e,buffer->requirements.size),type},NULL))),BV_MEMORY);
  bv_test_result(e,bv_bind_buffer_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(buffer),bv_test_handle(memory),bv_words(e,0)},NULL),0);
  return buffer;
}
static Term retirement_list(Env e,BvRow* a,BvRow* am,BvRow* b,BvRow* bm,unsigned count) {
  Term list=term_pak(CID(Nil),0);
  for(unsigned j=count;j>0;j--) {
    bool second=(j-1)%2;
    Term pair=io_tup(e,bv_test_handle(second ? b : a),bv_test_handle(second ? bm : am));
    list=io_node(e,CID(Con),pair,list);
  }
  return list;
}
static void retirement_call(Env e,BvRow* owner,BvRow* a,BvRow* am,BvRow* b,BvRow* bm,unsigned count,uint32_t expected) {
  Term args[]={bv_test_handle(owner),retirement_list(e,a,am,b,bm,count)};
  bv_test_result(e,bv_retire_buffers(e,args,NULL),expected);
}
static void retirement_atomic(Env e,BvRow* owner) {
  unsigned rows=probe_rows(),allocations=bv_test_live_allocations;
  BvRow* a=retirement_buffer(e,owner),*b=retirement_buffer(e,owner),*am=bv_bound_memory(a),*bm=bv_bound_memory(b);
  unsigned live=bv_test_live_allocations;
  retirement_call(e,owner,a,am,b,bm,0,0);
  retirement_call(e,owner,a,am,b,am,2,BV_ARGUMENT);
  assert(!a->retired && !am->retired && !b->retired && !bm->retired);
  BvRow* alias=bv_get(bv_key(e,bv_test_value(e,bv_create_buffer(e,(Term[]){bv_test_handle(owner),bv_node(e,CID(BufferCreateInfo),3,(Term[]){64,0,67})},NULL))),BV_BUFFER);
  bv_test_result(e,bv_bind_buffer_memory(e,(Term[]){bv_test_handle(owner),bv_test_handle(alias),bv_test_handle(bm),bv_words(e,0)},NULL),0);
  retirement_call(e,owner,a,am,b,bm,2,BV_LIFETIME);
  assert(!a->retired && !am->retired && !b->retired && !bm->retired);
  bv_test_result(e,bv_destroy_buffer(e,(Term[]){bv_test_handle(owner),bv_test_handle(alias)},NULL),0);
  bv_test_alloc_at=0;bv_test_alloc_fail=1;
  retirement_call(e,owner,a,am,b,bm,9,BV_LIMIT);bv_test_alloc_fail=0;
  assert(!a->retired && !am->retired && !b->retired && !bm->retired && bv_test_live_allocations==live);
  bv_test_realloc_at=0;bv_test_realloc_fail=1;
  retirement_call(e,owner,a,am,b,bm,17,BV_LIMIT);bv_test_realloc_fail=0;
  assert(!a->retired && !am->retired && !b->retired && !bm->retired && bv_test_live_allocations==live);
  BvDevice* device=owner->context;uint32_t health=device->health;device->health=BV_LOST;
  retirement_call(e,owner,a,am,b,bm,2,(uint32_t)VK_ERROR_DEVICE_LOST);device->health=health;
  assert(!a->retired && !am->retired && !b->retired && !bm->retired);
  uint32_t aid=a->id,bid=b->id;
  retirement_call(e,owner,a,am,b,bm,17,0);
  retirement_call(e,owner,a,am,b,bm,17,0);
  assert(a->retired && am->retired && b->retired && bm->retired && bv_test_live_allocations==live);
  bv_test_one(e,bv_collect_retired,owner,0);
  assert(!bv_get(aid,BV_BUFFER) && !bv_get(bid,BV_BUFFER));
  assert(probe_rows()==rows && bv_test_live_allocations==allocations);
  puts("Atomic retirement late bad pair/real alias, scratch allocation OOM, empty/duplicates/idempotence and exact metadata cleanup passed");
}
static Term test_retire_buffers(Env e,Term* f,IoWork* w) {
  static bool checked,atomic_checked;
  BvRow* owner=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_DEVICE);
  if(!atomic_checked && owner) {atomic_checked=true;retirement_atomic(e,owner);}
  Term result=bv_retire_buffers(e,f,w);
  BvRow* command=owner ? bv_active(owner,NULL) : NULL;
  BvRow* buffer=NULL;
  for (BvRow* row=bv_rows;command && row;row=row->next) if(row->kind==BV_BUFFER && row->parent==owner && row->retired && bv_may_reach_depth(command,row,BV_KIND_COUNT)) {buffer=row;break;}
  if (!checked && term_aux(result)==CID(Done) && owner && buffer && command && bv_may_reach_depth(command,buffer,BV_KIND_COUNT)) {
    checked=true;
    BvDevice* device=owner->context;
    uint32_t id=buffer->id;
    unsigned allocations=bv_test_live_allocations;
    bv_test_one(e,bv_collect_retired,owner,0);
    assert(bv_get(id,BV_BUFFER)==buffer && bv_test_live_allocations==allocations);
    bv_test_one(e,bv_reset_command_buffer,command,BV_LIFETIME);
    assert(bv_idle(owner)==VK_SUCCESS);
    BvDep* references=command->deps;
    PFN_vkResetCommandBuffer reset=device->ResetCommandBuffer;
    device->ResetCommandBuffer=bv_test_reset_error;
    bv_test_one(e,bv_reset_command_buffer,command,(uint32_t)VK_ERROR_OUT_OF_HOST_MEMORY);
    device->ResetCommandBuffer=reset;
    bv_test_one(e,bv_collect_retired,owner,0);
    assert(command->deps==references && bv_get(id,BV_BUFFER)==buffer && bv_test_live_allocations==allocations);
    BvRow* pool=bv_test_pool(e,owner);
    BvRow* fresh=bv_test_command(e,owner,pool);
    bv_test_one(e,bv_begin_command_buffer,fresh,0);
    Term fill[]={bv_test_handle(fresh),bv_test_handle(buffer),bv_words(e,0),bv_words(e,4),0};
    bv_test_result(e,bv_cmd_fill_buffer(e,fill,NULL),BV_LIFETIME);
    Term destroy[]={bv_test_handle(owner),bv_test_handle(pool)};
    bv_test_result(e,bv_destroy_command_pool(e,destroy,NULL),0);
    assert(bv_test_live_allocations==allocations);
    puts("Retirement retained pending and failed-reset references and sealed future recording passed");
  }
  return result;
}
