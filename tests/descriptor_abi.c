#include <assert.h>
static void descriptor_fields(Env e,Term v,unsigned n,Term* p) {spare_free(e,cls_fit(n),ctr_take(e,v,n,p));}
static Term descriptor_abi(Env e,Term* f,IoWork* w) {
  Term p[9],item[2];descriptor_fields(e,f[0],2,item);descriptor_fields(e,item[0],4,p);
  assert(p[0]==9 && p[1]==1 && p[2]==2 && p[3]==16);
  descriptor_fields(e,item[1],2,item);descriptor_fields(e,item[0],4,p);
  assert(p[0]==3 && p[1]==0 && p[2]==4 && p[3]==17 && term_aux(item[1])==CID(Nil));
  descriptor_fields(e,f[1],2,p);assert(p[0]==7);descriptor_fields(e,p[1],2,item);descriptor_fields(e,item[0],2,p);assert(p[0]==0 && p[1]==11);
  descriptor_fields(e,item[1],2,item);descriptor_fields(e,item[0],2,p);assert(p[0]==1 && p[1]==13 && term_aux(item[1])==CID(Nil));
  descriptor_fields(e,f[2],2,item);uint64_t uniform_tag=term_aux(item[0]);assert(term_tag(item[0])==TAG_CTR);descriptor_fields(e,item[0],3,p);assert(p[0]==3 && p[1]==1);
  Term values[2],v[5];descriptor_fields(e,p[2],2,values);descriptor_fields(e,values[0],5,v);
  assert(v[0]==23 && v[1]==0x12345678 && v[2]==0x9abcdef0 && v[3]==7 && v[4]==1 && term_aux(values[1])==CID(Nil));
  descriptor_fields(e,item[1],2,item);assert(term_tag(item[0])==TAG_CTR && term_aux(item[0])!=uniform_tag);descriptor_fields(e,item[0],3,p);assert(p[0]==9 && !p[1]);
  descriptor_fields(e,p[2],2,values);descriptor_fields(e,values[0],3,v);assert(v[0]==29 && v[1]==31 && v[2]==4 && term_aux(values[1])==CID(Nil) && term_aux(item[1])==CID(Nil));
  descriptor_fields(e,f[3],9,p);for(unsigned j=0;j<6;j++)assert(p[j]==(unsigned[]){1,0,1,2,3,4}[j]);assert(f32_unbox(p[6])==0.25f && f32_unbox(p[7])==3.5f && p[8]==5);
  descriptor_fields(e,f[4],4,p);assert(p[1]==1 && p[2]==17 && p[3]==64);descriptor_fields(e,p[0],2,item);assert(term_loc(item[0])==37);descriptor_fields(e,item[1],2,item);assert(term_loc(item[0])==41 && term_aux(item[1])==CID(Nil));
  descriptor_fields(e,f[5],2,item);descriptor_fields(e,item[0],4,p);assert(p[0]==3 && p[1]==0 && p[2]==4 && p[3]==17);descriptor_fields(e,item[1],2,item);descriptor_fields(e,item[0],4,p);assert(p[0]==9 && p[1]==1 && p[2]==2 && p[3]==16 && term_aux(item[1])==CID(Nil));
  puts("Emitted descriptor ABI schemas, typed writes, arrays, U64, F32 and ordered layouts passed");return term_pak(CID(Unit),0);
}
__attribute__((constructor)) static void descriptor_register(void) {io_eff(CID(probe),descriptor_abi);}
