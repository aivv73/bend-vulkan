#include <assert.h>
static void abi_unpack(Env e,Term value,uint32_t count,Term* fields) {
  spare_free(e,cls_fit(count),ctr_take(e,value,count,fields));
}
static void abi_lanes(Env e,Term value,uint32_t count,const uint32_t* expected) {
  Term fields[16];abi_unpack(e,value,count,fields);
  for(uint32_t j=0;j<count;j++)assert((uint32_t)fields[j]==expected[j]);
}
static Term presentation_abi_probe(Env e,Term* f,IoWork* w) {
  abi_lanes(e,f[0],3,(uint32_t[]){11,13,17});
  abi_lanes(e,f[1],10,(uint32_t[]){19,3,44,0,800,450,16,1,1,2});
  abi_lanes(e,f[2],12,(uint32_t[]){2,8,0xffffffff,0xffffffff,1,2,4096,8192,1,1,3,16});
  Term fields[6];abi_unpack(e,f[3],6,fields);
  assert(fields[0]==800 && fields[1]==450 && fields[2]==1 && fields[3]==0 && fields[4]==1);
  Term list[2];abi_unpack(e,fields[5],2,list);abi_lanes(e,list[0],2,(uint32_t[]){119,1});assert(term_aux(list[1])==CID(Nil));
  abi_lanes(e,f[4],2,(uint32_t[]){7,1});
  for(unsigned j=5;j<9;j++)for(unsigned k=j+1;k<9;k++)assert(f[j]!=f[k]);
  for(unsigned j=9;j<13;j++)for(unsigned k=j+1;k<13;k++)assert(f[j]!=f[k]);
  abi_lanes(e,f[13],2,(uint32_t[]){23,1024});
  abi_lanes(e,f[14],2,(uint32_t[]){0x89abcdef,0x1234567});
  puts("Presentation ABI records, Boolean lanes, events, lifecycle variants and U64 passed");
  return term_pak(CID(Unit),0);
}
__attribute__((constructor)) static void register_presentation_abi(void) {
  io_eff(CID(probe),presentation_abi_probe);
}
