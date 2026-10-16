#include <assert.h>
static void graphics_fields(Env e,Term value,uint32_t count,Term* fields) {
  spare_free(e,cls_fit(count),ctr_take(e,value,count,fields));
}
static Term graphics_abi_probe(Env e,Term* f,IoWork* w) {
  Term p[14],item[2],b[4];graphics_fields(e,f[0],14,p);
  for (unsigned j=0;j<4;j++) assert(p[j]==(uint32_t[]){11,13,17,19}[j]);
  graphics_fields(e,p[4],2,item);graphics_fields(e,item[0],3,b);
  assert(b[0]==7 && b[1]==24 && b[2]==1 && term_aux(item[1])==CID(Nil));
  graphics_fields(e,p[5],2,item);graphics_fields(e,item[0],4,b);
  assert(b[0]==3 && b[1]==7 && b[2]==106 && b[3]==12 && term_aux(item[1])==CID(Nil));
  for (unsigned j=6;j<14;j++) assert(p[j]==(uint32_t[]){3,2,1,1,1,0,6,15}[j-6]);
  graphics_fields(e,f[1],14,p);
  assert(term_aux(p[4])==CID(Nil) && term_aux(p[5])==CID(Nil));
  for (unsigned j=6;j<14;j++) assert(p[j]==(uint32_t[]){4,0,0,0,0,0,0,7}[j-6]);
  graphics_fields(e,f[2],4,p);assert(term_aux(p[0])==CID(Nil) && p[1]==1 && p[2]==17 && p[3]==128);
  graphics_fields(e,f[3],4,p);assert(term_aux(p[0])==CID(Nil) && !p[1] && !p[2] && !p[3]);
  graphics_fields(e,f[4],6,p);
  for(unsigned j=0;j<6;j++) assert(f32_unbox(p[j])==(float[]){-0.5f,0.25f,32,64,0,1}[j]);
  graphics_fields(e,f[5],5,p);
  for(unsigned j=0;j<5;j++) assert(p[j]==(uint32_t[]){6,2,3,4294967293u,5}[j]);
  assert(term_tag(f[6])==TAG_PAK && term_loc(f[6])==2147483648u);
  graphics_fields(e,f[7],2,p);assert(p[0]==0x12345678 && p[1]==0x9abcdef0);
  graphics_fields(e,f[8],2,item);assert(item[0]==0x07230203);
  graphics_fields(e,item[1],2,item);assert(item[0]==UINT32_MAX && term_aux(item[1])==CID(Nil));
  puts("Emitted graphics ABI: 14 pipeline lanes, 4 layout lanes, F32, signed bits, U64 and word lists passed");
  return term_pak(CID(Unit),0);
}
__attribute__((constructor)) static void register_graphics_abi(void) {io_eff(CID(probe),graphics_abi_probe);}
