#include <assert.h>
static void abi_fields(Env e,Term value,uint32_t count,Term* fields) {
  spare_free(e,cls_fit(count),ctr_take(e,value,count,fields));
}
static void abi_words(Env e,Term value,uint32_t count,const uint32_t* expected) {
  Term fields[12];abi_fields(e,value,count,fields);
  for (uint32_t j=0;j<count;j++) assert((uint32_t)fields[j]==expected[j]);
}
static void abi_color(Env e,Term value) {
  Term lanes[4];abi_fields(e,value,4,lanes);
  const uint32_t bits[]={0x3e800000,0xbf000000,0x3f800000,0x80000000};
  const float expected[]={0.25f,-0.5f,1.0f,-0.0f};
  for (unsigned j=0;j<4;j++) {
    float actual=f32_unbox(lanes[j]);uint32_t raw;memcpy(&raw,&actual,4);
    assert(raw==bits[j] && actual==expected[j]);
  }
}
static Term image_abi_probe(Env e, Term* f, IoWork* w) {
  abi_color(e,f[0]);Term list=f[1],item[2];
  abi_fields(e,list,2,item);assert(term_tag(item[0])==TAG_CTR);abi_color(e,item[0]);list=item[1];
  abi_fields(e,list,2,item);assert(term_tag(item[0])==TAG_PAK);
  Term depth=term_loc(item[0]);assert((uint32_t)depth==0x3f000000 && f32_unbox(depth)==0.5f);list=item[1];
  abi_fields(e,list,2,item);assert(term_tag(item[0])==TAG_PAK && term_loc(item[0])==0 && term_aux(item[1])==CID(Nil));
  Term pass[5];abi_fields(e,f[2],5,pass);assert(pass[1]==1 && pass[2]==126 && pass[3]==2 && pass[4]==1);
  abi_fields(e,pass[0],2,item);abi_words(e,item[0],3,(uint32_t[]){37,1,0});assert(term_aux(item[1])==CID(Nil));
  abi_fields(e,f[3],5,pass);assert(term_aux(pass[0])==CID(Nil));for(unsigned j=1;j<5;j++) assert(pass[j]==0);
  Term fb[4];abi_fields(e,f[4],4,fb);assert(fb[0]==17 && fb[2]==23 && fb[3]==29);
  abi_fields(e,fb[1],2,item);assert(term_tag(item[0])==TAG_PAK && term_loc(item[0])==19 && term_aux(item[1])==CID(Nil));
  abi_words(e,f[5],12,(uint32_t[]){0x12345678,0x9abcdef0,31,37,1,2,3,4,41,43,47,53});
  abi_words(e,f[6],10,(uint32_t[]){59,1,2,3,4,5,6,7,8,9});
  abi_words(e,f[7],6,(uint32_t[]){37,61,67,3,2,7});
  abi_words(e,f[8],7,(uint32_t[]){71,1,1,2,3,4,5});
  abi_words(e,f[9],5,(uint32_t[]){37,1,0,3,0});
  abi_words(e,f[10],4,(uint32_t[]){73,79,83,89});
  abi_words(e,f[11],8,(uint32_t[]){1,2,3,4,5,6,0x12345678,0x9abcdef0});
  assert((uint32_t)f[12]==0x3f000000 && f32_unbox(f[12])==0.5f);
  puts("Installed Bend F32, nested records, variants, Some/None and U64 ABI passed");
  return term_pak(CID(Unit),0);
}
__attribute__((constructor)) static void register_image_abi(void) {
  io_eff(CID(probe),image_abi_probe);
}
