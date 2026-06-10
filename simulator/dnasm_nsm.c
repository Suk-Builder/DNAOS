/* DNAsm NSM -- Neural State Machine Interpreter
 *
 * DNAOS Major Architecture Upgrade: Von Neumann SM -> Neural SM
 * Three-layer memory modelled after the brain:
 *   - st[k] holds float nsm_val (voltage/conductance/current)
 *   - 64x64 memristor crossbar for analog compute
 *
 * ISA (37 opcodes):
 *   Molecular (12): UNZIP/HYB/DISPL/CLEAVE/LIGATE/POLY/MELT/ANNEAL/FIND/COUNT/SPLIT/MIX
 *   I/O    (7): COPY/BURN/READ/LOAD/TEMP/NOP/HALT
 *   GPU    (11): PARA/REDUCE_SUM/REDUCE_MAX/DOT/MAD/LERP/CLAMP/SIN/COS/FMA/SYNC
 *   Control (9): LABEL/JMP/JZ/JNZ/JE/JNE/CMP/CALL/RET
 *   NSM Core (6): DAC/SET/RST/VMM/STDP/CHEM
 *   Timing  (1): SLEEP
 *   Reagent (1): REAGENT
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <time.h>
#include <unistd.h>

#include "nsm_backend.h"

#define MAX_STRANDS 10000
#define MAX_LEN     256
#define NTUBES      64
#define MAX_PROG    4096
#define NUM_PHYSICAL_LIMIT 500
#define VAL_SEQ     "ACGTACGTACGTACGT"
#define MAX_LABELS  256
#define CALL_STACK  64
#define N_REAGENTS  5

/* 【---- ISA 操作码 Table ----】 */
enum {
    OP_UNZIP=0, OP_HYB,  OP_DISPL, OP_CLEAVE,
    OP_LIGATE,  OP_POLY, OP_MELT,  OP_ANNEAL,
    OP_FIND,    OP_COUNT,OP_SPLIT, OP_MIX,
    OP_COPY,    OP_BURN, OP_READ,  OP_LOAD,
    OP_TEMP,    OP_NOP,  OP_HALT,
    OP_PARA,    OP_REDUCE_SUM, OP_REDUCE_MAX,
    OP_DOT,     OP_MAD,  OP_LERP,  OP_CLAMP,
    OP_SIN,     OP_COS,  OP_FMA,   OP_SYNC,
    OP_LABEL,   OP_JMP,  OP_JZ,    OP_JNZ,
    OP_JE,      OP_JNE,  OP_CMP,   OP_CALL, OP_RET,
    OP_DAC,     OP_SET,  OP_RST,   OP_VMM,
    OP_STDP,    OP_CHEM,
    OP_SLEEP,   OP_REAGENT,
    N_OPS
};
const char*op_name[]={
    "UNZIP","HYB","DISPL","CLEAVE","LIGATE","POLY","MELT","ANNEAL",
    "FIND","COUNT","SPLIT","MIX","COPY","BURN","READ","LOAD",
    "TEMP","NOP","HALT","PARA","REDUCE_SUM","REDUCE_MAX",
    "DOT","MAD","LERP","CLAMP","SIN","COS","FMA","SYNC",
    "LABEL","JMP","JZ","JNZ","JE","JNE","CMP","CALL","RET",
    "DAC","SET","RST","VMM","STDP","CHEM","SLEEP","REAGENT"
};

int b2d(char c){switch(c){case'A':case'a':return 0;case'T':case't':return 1;case'C':case'c':return 2;case'G':case'g':return 3;}return 0;}
char d2b(int d){return"ATCG"[d&3];}
void enc_op(int op,char o[4]){o[0]=d2b(op/16);o[1]=d2b((op/4)%4);o[2]=d2b(op%4);o[3]=0;}
int dec_op(const char c[3]){int cd=b2d(c[0])*16+b2d(c[1])*4+b2d(c[2]);return(cd<N_OPS)?cd:OP_NOP;}

/* 【---- 试管: strands (molecular) + float nsm_val (neural) ----】 */
typedef struct{char seq[MAX_LEN];int len;}Strand;
typedef struct{Strand*s;int n,cap;float nsm_val;}Tube;
Tube st[NTUBES],dt[NTUBES];
double temp=37.0;

/* 【---- NSM Runtime ----】 */
static MemristorArray crossbar;
static int nsm_initialized=0;

/* 【---- Control Flow ----】 */
typedef struct{char name[32];int addr;}Label;
static Label labels[MAX_LABELS];static int n_labels=0;
static int call_stack[CALL_STACK];static int call_sp=0;
static int flag_z=0,flag_e=0,flag_g=0,flag_l=0;

/* 【---- 试剂 tracking ----】 */
static const char*reagent_name[N_REAGENTS]={"Hg2+","Ag+","EDTA","DNA_chain","Buffer"};
static const char*reagent_unit[N_REAGENTS]={"mg","mg","ml","pmol","ml"};
static double reagent_total[N_REAGENTS]={0};
static int reagent_count[N_REAGENTS]={0};

static int warp_start=0,warp_end=0;

/* ======================================================================== */
/* 【试管 HELPERS (molecular 层)】 */
/* ======================================================================== */
void init_tubes(){
    for(int i=0;i<NTUBES;i++){
        st[i].s=(Strand*)malloc(MAX_STRANDS*sizeof(Strand));
        st[i].n=0;st[i].cap=MAX_STRANDS;st[i].nsm_val=0.0f;
        dt[i].s=(Strand*)malloc(MAX_STRANDS*sizeof(Strand));
        dt[i].n=0;dt[i].cap=MAX_STRANDS;dt[i].nsm_val=0.0f;
    }
    n_labels=0;call_sp=0;flag_z=flag_e=flag_g=flag_l=0;
    memset(reagent_total,0,sizeof(reagent_total));
    memset(reagent_count,0,sizeof(reagent_count));
    if(!nsm_initialized){nsm_init(&crossbar);nsm_initialized=1;}
}
void free_tubes(){for(int i=0;i<NTUBES;i++){free(st[i].s);free(dt[i].s);}}
void clear_t(Tube*t){t->n=0;t->nsm_val=0.0f;}
void add_s(Tube*t,const char*seq){
    if(t->n>=t->cap)return;
    int len=strlen(seq);if(len>=MAX_LEN)len=MAX_LEN-1;
    memcpy(t->s[t->n].seq,seq,len);t->s[t->n].seq[len]=0;t->s[t->n].len=len;t->n++;
}
void add_n(Tube*t,long long N){
    long long phys=(N>NUM_PHYSICAL_LIMIT)?NUM_PHYSICAL_LIMIT:N;
    for(int i=0;i<phys&&t->n<t->cap;i++){
        memcpy(t->s[t->n].seq,VAL_SEQ,16);t->s[t->n].seq[16]=0;t->s[t->n].len=16;t->n++;
    }
    t->nsm_val=(float)N;
}

char comp(char c){switch(c){case'A':case'a':return'T';case'T':case't':return'A';case'C':case'c':return'G';case'G':case'g':return'C';}return c;}
void revcomp(const char*in,char*out){int len=strlen(in);for(int i=0;i<len;i++)out[i]=comp(in[len-1-i]);out[len]=0;}
int is_comp(const char*a,const char*b){int la=strlen(a),lb=strlen(b);if(la!=lb)return 0;for(int i=0;i<la;i++)if(comp(a[i])!=b[i])return 0;return 1;}

void do_unzip(int dst){Tube*src=&dt[dst],*out=&st[dst];clear_t(out);int orig_n=src->n;for(int i=0;i<orig_n&&out->n+1<out->cap;i++){char rc[MAX_LEN];revcomp(src->s[i].seq,rc);add_s(out,src->s[i].seq);add_s(out,rc);}}
void do_hyb(int idx){Tube*src=&st[idx],*out=&dt[idx];clear_t(out);int used[MAX_STRANDS]={0};for(int i=0;i<src->n;i++){if(used[i])continue;for(int j=i+1;j<src->n;j++){if(!used[j]&&is_comp(src->s[i].seq,src->s[j].seq)){if(out->n<out->cap)add_s(out,src->s[i].seq);used[i]=used[j]=1;break;}}}}
void do_displ(int idx,const char*inc){Tube*d=&dt[idx],*s=&st[idx];int ilen=strlen(inc);for(int i=0;i<d->n;i++){char rc[MAX_LEN];revcomp(d->s[i].seq,rc);int mi=0,mr=0,ln=d->s[i].len;for(int j=0;j<ln;j++){if(j<ilen&&comp(d->s[i].seq[j])==inc[j])mi++;if(comp(d->s[i].seq[j])==rc[j])mr++;}if(mi>mr&&s->n<s->cap){add_s(s,rc);memcpy(d->s[i].seq,inc,ilen);d->s[i].seq[ilen]=0;d->s[i].len=ilen;}}}
void do_poly(int dst,int src,const char*pr){Tube*S=&st[src],*D=&st[dst];for(int i=0;i<S->n&&D->n<D->cap;i++){if(strstr(S->s[i].seq,pr)){char rc[MAX_LEN];revcomp(S->s[i].seq,rc);add_s(D,rc);}}}
void do_cleave(int idx,const char*site){Tube*t=&st[idx];Strand R[MAX_STRANDS];int rn=0,sl=strlen(site);for(int i=0;i<t->n&&rn<MAX_STRANDS;i++){char*p=t->s[i].seq;int prev=0;while((p=strstr(p+prev,site))!=NULL&&rn<MAX_STRANDS){int b=p-t->s[i].seq;if(b>prev){memcpy(R[rn].seq,t->s[i].seq+prev,b-prev);R[rn].seq[b-prev]=0;R[rn].len=b-prev;rn++;}prev=b+sl;p++;}if(prev<t->s[i].len&&rn<MAX_STRANDS){strcpy(R[rn].seq,t->s[i].seq+prev);R[rn].len=strlen(R[rn].seq);rn++;}}if(rn>t->cap)rn=t->cap;memcpy(t->s,R,rn*sizeof(Strand));t->n=rn;}
void do_ligate(int dst,int a,int b){Tube*ta=&st[a],*tb=&st[b],*D=&st[dst];clear_t(D);for(int i=0;i<ta->n&&D->n<D->cap;i++)for(int j=0;j<tb->n&&D->n<D->cap;j++){int la=ta->s[i].len,lb=tb->s[j].len;if(la>0&&lb>0&&comp(ta->s[i].seq[la-1])==tb->s[j].seq[0]){strcpy(D->s[D->n].seq,ta->s[i].seq);strcat(D->s[D->n].seq,tb->s[j].seq);D->s[D->n].len=strlen(D->s[D->n].seq);D->n++;}}}
void do_melt(int idx,double t){temp=t;if(temp>65.0)do_unzip(idx);}
void do_anneal(int idx,double t){temp=t;if(temp<55.0)do_hyb(idx);}
int do_find(int idx,const char*pat){Tube*T=&st[idx];int f=0;for(int i=0;i<T->n;i++)if(strstr(T->s[i].seq,pat))f++;return f;}
void do_count(int idx){Tube*t=&st[idx];t->nsm_val=(float)t->n;}
void do_split(int idx,int n){Tube*t=&st[idx];if(n>0&&n<t->n){Tube*out=&dt[idx];clear_t(out);for(int i=n;i<t->n&&out->n<out->cap;i++)add_s(out,t->s[i].seq);t->n=n;}}
void do_mix(int dst,int a,int b){Tube*da=&st[dst];clear_t(da);for(int i=0;i<st[a].n&&da->n<da->cap;i++)add_s(da,st[a].s[i].seq);for(int i=0;i<st[b].n&&da->n<da->cap;i++)add_s(da,st[b].s[i].seq);}
void do_read_tube(int idx){Tube*t=&st[idx];printf("  READ st[%d]: %d strands [nsm_val=%.4f]\n",idx,t->n,t->nsm_val);for(int i=0;i<t->n&&i<3;i++)printf("    [%d] %s (len=%d)\n",i,t->s[i].seq,t->s[i].len);if(t->n>3)printf("    ... (%d more)\n",t->n-3);}
void do_burn(int idx){clear_t(&st[idx]);clear_t(&dt[idx]);}
void do_copy(int idx,int cycles){Tube*t=&st[idx];for(int c=0;c<cycles&&t->n<t->cap/2;c++){int cur=t->n;for(int i=0;i<cur&&t->n<t->cap;i++){char rc[MAX_LEN];revcomp(t->s[i].seq,rc);add_s(t,rc);}}if(t->nsm_val>0){t->nsm_val*=(1<<cycles);}}

/* ======================================================================== */
/* 【NSM CORE OPERATIONS (with imm flags)】 */
/* ======================================================================== */

/* Parser: returns tube index. For plain integers N, sets *is_imm=1 and
 * stores the value in st[N&63].nsm_val. For st[k], *is_imm=0.
 * Integer indices use GETV (idx == value for imms).
 * Float params use fval snapshot to survive execution-side mutations. */
static int parse_tube(char*tk,int*is_imm){
    if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){
        char*q=tk+2;if(*q=='[')q++;
        *is_imm=0;
        return atoi(q)&63;
    }else{
        int idx=atoi(tk)&63;
        st[idx].nsm_val=(float)atof(tk);
        *is_imm=1;
        return idx;
    }
}

#define GETV(idx,imm) ((imm)?(idx):(int)st[(idx)].nsm_val)

/* 【DAC st[krow] st[kcol] voltage_mv -- 写入 voltage to crossbar.V[row]】 */
void do_dac(int row_idx,int col_idx,float voltage,int imm0,int imm1){
    (void)col_idx;(void)imm1;
    int row=GETV(row_idx,imm0);
    if(row<0)row=0;if(row>=NSM_ROWS)row=NSM_ROWS-1;
    crossbar.V[row]=voltage * 1e-3f;
    printf("  [DAC] V[%d] = %.3f V\n",row,crossbar.V[row]);
}

/* SET st[row] st[col] st[pw] -- potentiation pulse (LTP)
 * pw uses fval snapshot when imm so COUNT/etc don't corrupt it */
void do_set(int row_idx,int col_idx,int pw_idx,int imm0,int imm1,int imm2,float fval_pw){
    int row=GETV(row_idx,imm0);
    int col=GETV(col_idx,imm1);
    float pw=imm2?fval_pw:st[pw_idx].nsm_val;
    if(row<0)row=0;if(row>=NSM_ROWS)row=NSM_ROWS-1;
    if(col<0)col=0;if(col>=NSM_COLS)col=NSM_COLS-1;
    nsm_set(&crossbar,row,col,pw,1.0f);
    printf("  [SET] G[%d][%d] += LTP (pw=%.1f ns)\n",row,col,pw);
}

/* 【RST st[row] st[col] st[pw] -- depression pulse (LTD)】 */
void do_rst(int row_idx,int col_idx,int pw_idx,int imm0,int imm1,int imm2,float fval_pw){
    int row=GETV(row_idx,imm0);
    int col=GETV(col_idx,imm1);
    float pw=imm2?fval_pw:st[pw_idx].nsm_val;
    if(row<0)row=0;if(row>=NSM_ROWS)row=NSM_ROWS-1;
    if(col<0)col=0;if(col>=NSM_COLS)col=NSM_COLS-1;
    nsm_reset(&crossbar,row,col,pw,1.0f);
    printf("  [RST] G[%d][%d] -= LTD (pw=%.1f ns)\n",row,col,pw);
}

/* 【VMM -- vector-matrix 乘法】 */
void do_vmm(void){
    nsm_vmm(&crossbar);
    printf("  [VMM] I = G^T * V done\n");
}

/* 【读取 st[dst] st[row] st[col] -- 读取 conductance】 */
void do_read_cond(int dst_idx,int row_idx,int col_idx,int imm1,int imm2){
    int row=GETV(row_idx,imm1);
    int col=GETV(col_idx,imm2);
    if(row<0)row=0;if(row>=NSM_ROWS)row=NSM_ROWS-1;
    if(col<0)col=0;if(col>=NSM_COLS)col=NSM_COLS-1;
    float g=nsm_read(&crossbar,row,col);
    st[dst_idx].nsm_val=g;
    printf("  [READ] G[%d][%d] = %.6f S -> st[%d]\n",row,col,g,dst_idx);
}

/* 【STDP st[pre] st[post] st[dt] -- spike-timing dependent plasticity】 */
void do_stdp(int pre_idx,int post_idx,int dt_idx,int imm0,int imm1,int imm2,float fval_dt){
    int pre=GETV(pre_idx,imm0);
    int post=GETV(post_idx,imm1);
    float dt=imm2?fval_dt:st[dt_idx].nsm_val;
    if(pre<0)pre=0;if(pre>=NSM_ROWS)pre=NSM_ROWS-1;
    if(post<0)post=0;if(post>=NSM_COLS)post=NSM_COLS-1;
    float pre_t=0.0f,post_t=dt;
    if(dt<0){pre_t=-dt;post_t=0.0f;}
    nsm_stdp(&crossbar,pre,post,pre_t,post_t);
    printf("  [STDP] pre=%d post=%d dt=%.2f ms (%s)\n",pre,post,dt,(dt>0)?"LTP":"LTD");
}

/* 【CHEM st[类型] st[intensity] -- chemical neuromodulation】 */
void do_chem(int type_idx,int intensity_idx,int imm0,int imm1,float fval_intensity){
    int type=GETV(type_idx,imm0);
    float intensity=imm1?fval_intensity:st[intensity_idx].nsm_val;
    if(intensity<0.0f)intensity=0.0f;if(intensity>1.0f)intensity=1.0f;
    nsm_chem_mod(&crossbar,type,intensity);
    printf("  [CHEM] type=%d intensity=%.4f\n",type,intensity);
}

/* ======================================================================== */
/* 【GPU 并行 PRIMITIVES】 */
/* ======================================================================== */

void do_para(int start,int end){warp_start=start&63;warp_end=(end>63?63:end)&63;}
void do_reduce_sum(int dst,int start,int end){
    float sum=0.0f;int s=start&63,e=(end>63?63:end)&63;
    for(int i=s;i<=e;i++)sum+=st[i].nsm_val;
    st[dst&63].nsm_val=sum;
}
void do_reduce_max(int dst,int start,int end){
    float mx=-1e38f;int s=start&63,e=(end>63?63:end)&63;
    for(int i=s;i<=e;i++)if(st[i].nsm_val>mx)mx=st[i].nsm_val;
    st[dst&63].nsm_val=mx;
}
void do_dot(int dst,int a_start,int b_start,int N){
    float sum=0.0f;int a=a_start&63,b=b_start&63;
    for(int i=0;i<N&&i<64;i++)sum+=st[(a+i)&63].nsm_val*st[(b+i)&63].nsm_val;
    st[dst&63].nsm_val=sum;
}
void do_mad(int dst,int a,int b){int d=dst&63,A=a&63,B=b&63;st[d].nsm_val=st[A].nsm_val*st[B].nsm_val+st[d].nsm_val;}
void do_lerp(int dst,int a,int b,float t){
    int d=dst&63,A=a&63,B=b&63;
    st[d].nsm_val=st[A].nsm_val*(1.0f-t)+st[B].nsm_val*t;
}
void do_clamp(int dst,float mn,float mx){int d=dst&63;if(st[d].nsm_val<mn)st[d].nsm_val=mn;if(st[d].nsm_val>mx)st[d].nsm_val=mx;}
void do_sin(int dst,int src){float x=st[src&63].nsm_val;st[dst&63].nsm_val=sinf(x);}
void do_cos(int dst,int src){float x=st[src&63].nsm_val;st[dst&63].nsm_val=cosf(x);}
void do_fma(int dst,int a,int b){int d=dst&63,A=a&63,B=b&63;st[d].nsm_val=st[A].nsm_val*st[B].nsm_val+st[d].nsm_val;}
void do_sync(void){}

/* ======================================================================== */
/* 【CONTROL FLOW】 */
/* ======================================================================== */

void do_cmp(int a,int b){
    float va=st[a&63].nsm_val,vb=st[b&63].nsm_val;
    flag_z=(fabsf(va)<1e-6f);flag_e=(fabsf(va-vb)<1e-6f);flag_g=(va>vb);flag_l=(va<vb);
}
int find_label(const char*name){
    for(int i=0;i<n_labels;i++)if(strcasecmp(labels[i].name,name)==0)return labels[i].addr;
    return -1;
}

/* ======================================================================== */
/* 【TIMING & 试剂】 */
/* ======================================================================== */

void do_sleep(int ms){
    if(ms<0)ms=0;if(ms>60000)ms=60000;
    printf("  [SLEEP %d ms]\n",ms);usleep(ms*1000);
}
void do_reagent(int tube_qty,int tube_type){
    int type=(int)st[tube_type].nsm_val;
    double qty=(double)st[tube_qty].nsm_val;
    if(type<0||type>=N_REAGENTS){printf("  [REAGENT ERR: invalid type %d]\n",type);return;}
    reagent_total[type]+=qty;reagent_count[type]++;
    printf("  [REAGENT %s %.2f %s]\n",reagent_name[type],qty,reagent_unit[type]);
}
void do_reagent_imm(int tube_qty,int type){
    double qty=(double)st[tube_qty].nsm_val;
    if(type<0||type>=N_REAGENTS){printf("  [REAGENT ERR: invalid type %d]\n",type);return;}
    reagent_total[type]+=qty;reagent_count[type]++;
    printf("  [REAGENT %s %.2f %s]\n",reagent_name[type],qty,reagent_unit[type]);
}
void print_reagent_summary(){
    printf("\n=== Reagent Consumption Summary ===\n");
    for(int i=0;i<N_REAGENTS;i++)if(reagent_count[i]>0)printf("  %s: total=%.2f %s, times=%d\n",reagent_name[i],reagent_total[i],reagent_unit[i],reagent_count[i]);
}

/* ======================================================================== */
/* 【程序 & PARSER】 */
/* ======================================================================== */

typedef struct{int op;int tube[3];int imm[3];float fval[3];double val;char str[64];}Inst;
Inst prog[MAX_PROG];int prog_len=0;

#define PT(i) do{int _idx=(i)-1;I->tube[_idx]=parse_tube(tok[i],&ti##_idx);I->imm[_idx]=ti##_idx;I->fval[_idx]=st[I->tube[_idx]].nsm_val;}while(0)

void parse_line(const char*line,Inst*I){
    int ti[4]={0};
    memset(I,0,sizeof(*I));I->op=OP_NOP;
    char buf[512];strncpy(buf,line,511);buf[511]=0;
    char*c=strchr(buf,'#');if(c)*c=0;c=strchr(buf,';');if(c)*c=0;
    char*p=buf;while(*p&&isspace(*p))p++;if(!*p)return;
    char*colon=strchr(p,':');if(colon&&colon<p+32&&*(colon+1)){p=colon+1;while(*p&&isspace(*p))p++;}if(!*p)return;
    char tok[8][64];int nt=0;
    char*t=strtok(p," \t\n\r,");while(t&&nt<8){strncpy(tok[nt],t,63);tok[nt][63]=0;nt++;t=strtok(NULL," \t\n\r,");}
    if(nt==0)return;
    if(strlen(tok[0])==3&&strspn(tok[0],"ATCGatcg")==3){I->op=dec_op(tok[0]);}
    else{for(int i=0;i<N_OPS;i++)if(strcasecmp(tok[0],op_name[i])==0){I->op=i;break;}}

    if(I->op==OP_LABEL&&nt>=2){strncpy(I->str,tok[1],63);I->str[63]=0;}
    else if((I->op==OP_JMP||I->op==OP_JZ||I->op==OP_JNZ||I->op==OP_JE||I->op==OP_JNE||I->op==OP_CALL)&&nt>=2){
        strncpy(I->str,tok[1],63);I->str[63]=0;
    }
    else if(I->op==OP_RET){/* 【nothing】 */}
    else if(I->op==OP_CMP&&nt>=3){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=parse_tube(tok[2],&ti[1]);I->imm[1]=ti[1];I->fval[1]=st[I->tube[1]].nsm_val;
    }
    else if(I->op==OP_SLEEP&&nt>=2){
        char*tk=tok[1];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[0]=atoi(q)&63;I->val=-1;}
        else{I->tube[0]=0;I->val=atoll(tk);}
    }
    else if(I->op==OP_REAGENT&&nt>=3){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        char*tk=tok[2];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[1]=atoi(q)&63;I->val=-1;}
        else{I->val=atoll(tk);}
    }
    else if(I->op==OP_DAC&&nt>=4){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=parse_tube(tok[2],&ti[1]);I->imm[1]=ti[1];I->fval[1]=st[I->tube[1]].nsm_val;
        I->val=atof(tok[3]);
    }
    else if(I->op==OP_DAC&&nt>=3){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=0;
        I->val=atof(tok[2]);
    }
    else if((I->op==OP_SET||I->op==OP_RST)&&nt>=4){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=parse_tube(tok[2],&ti[1]);I->imm[1]=ti[1];I->fval[1]=st[I->tube[1]].nsm_val;
        I->tube[2]=parse_tube(tok[3],&ti[2]);I->imm[2]=ti[2];I->fval[2]=st[I->tube[2]].nsm_val;
    }
    else if(I->op==OP_READ&&nt>=4){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=parse_tube(tok[2],&ti[1]);I->imm[1]=ti[1];I->fval[1]=st[I->tube[1]].nsm_val;
        I->tube[2]=parse_tube(tok[3],&ti[2]);I->imm[2]=ti[2];I->fval[2]=st[I->tube[2]].nsm_val;
    }
    else if(I->op==OP_READ&&nt>=2){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=0;I->tube[2]=0;
    }
    else if(I->op==OP_STDP&&nt>=4){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=parse_tube(tok[2],&ti[1]);I->imm[1]=ti[1];I->fval[1]=st[I->tube[1]].nsm_val;
        I->tube[2]=parse_tube(tok[3],&ti[2]);I->imm[2]=ti[2];I->fval[2]=st[I->tube[2]].nsm_val;
    }
    else if(I->op==OP_CHEM&&nt>=3){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=parse_tube(tok[2],&ti[1]);I->imm[1]=ti[1];I->fval[1]=st[I->tube[1]].nsm_val;
    }
    else if(I->op==OP_VMM){/* 【no params】 */}
    else if(I->op==OP_PARA&&nt>=3){for(int i=1;i<nt&&i<=2;i++)I->tube[i-1]=parse_tube(tok[i],&ti[0]);}
    else if((I->op==OP_REDUCE_SUM||I->op==OP_REDUCE_MAX)&&nt>=4){
        for(int i=1;i<nt&&i<=3;i++)I->tube[i-1]=parse_tube(tok[i],&ti[0]);
    }
    else if(I->op==OP_DOT&&nt>=5){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=parse_tube(tok[2],&ti[1]);I->imm[1]=ti[1];I->fval[1]=st[I->tube[1]].nsm_val;
        I->tube[2]=parse_tube(tok[3],&ti[2]);I->imm[2]=ti[2];I->fval[2]=st[I->tube[2]].nsm_val;
        I->val=atoll(tok[4]);
    }
    else if((I->op==OP_MAD||I->op==OP_FMA)&&nt>=4){for(int i=1;i<nt&&i<=3;i++)I->tube[i-1]=parse_tube(tok[i],&ti[0]);}
    else if(I->op==OP_LERP&&nt>=5){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=parse_tube(tok[2],&ti[1]);I->imm[1]=ti[1];I->fval[1]=st[I->tube[1]].nsm_val;
        I->tube[2]=parse_tube(tok[3],&ti[2]);I->imm[2]=ti[2];I->fval[2]=st[I->tube[2]].nsm_val;
        I->val=atof(tok[4]);
    }
    else if(I->op==OP_CLAMP&&nt>=4){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->val=atof(tok[2]);I->tube[1]=atof(tok[3]);
    }
    else if((I->op==OP_SIN||I->op==OP_COS)&&nt>=3){
        I->tube[0]=parse_tube(tok[1],&ti[0]);I->imm[0]=ti[0];I->fval[0]=st[I->tube[0]].nsm_val;
        I->tube[1]=parse_tube(tok[2],&ti[1]);I->imm[1]=ti[1];I->fval[1]=st[I->tube[1]].nsm_val;
    }
    else{
        for(int i=1;i<nt&&i<=3;i++){
            char*tk=tok[i];
            if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[i-1]=atoi(q)&63;}
            else if((tk[0]=='d'||tk[0]=='D')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[i-1]=atoi(q)&63;}
            else if(tk[0]=='"'){strncpy(I->str,tk+1,63);I->str[63]=0;char*e=strchr(I->str,'"');if(e)*e=0;}
            else if(strchr(tk,'.'))I->val=atof(tk);
            else if(tk[0]>='0'&&tk[0]<='9')I->val=atoll(tk);
            else I->tube[i-1]=atoi(tk)&63;
        }
    }
    if(I->op==OP_LOAD&&nt>=3&&tok[2][0]=='"'){strncpy(I->str,tok[2]+1,63);char*e=strchr(I->str,'"');if(e)*e=0;}
    else if(I->op==OP_LOAD&&nt>=3)strncpy(I->str,tok[2],63);
}

/* 【Two-pass 加载】 */
void collect_labels(char lines[][512],int n_lines){
    n_labels=0;prog_len=0;
    Inst tmp;
    for(int i=0;i<n_lines;i++){
        parse_line(lines[i],&tmp);
        char*p=lines[i];while(*p&&isspace(*p))p++;
        if(tmp.op==OP_LABEL&&tmp.str[0]){
            if(n_labels<MAX_LABELS){
                strncpy(labels[n_labels].name,tmp.str,31);labels[n_labels].name[31]=0;
                labels[n_labels].addr=prog_len;
                n_labels++;
            }
        }
        if(tmp.op!=OP_NOP||(p&&*p&&*p!='\n'&&*p!='#'&&*p!=';'&&*p!='\r')){
            prog_len++;
        }
    }
}

void resolve_jumps(){
    for(int i=0;i<prog_len;i++){
        if(prog[i].op==OP_JMP||prog[i].op==OP_JZ||prog[i].op==OP_JNZ||
           prog[i].op==OP_JE||prog[i].op==OP_JNE||prog[i].op==OP_CALL){
            if(prog[i].str[0]){
                int addr=find_label(prog[i].str);
                if(addr>=0)prog[i].val=addr;
                else printf("[WARN] Undefined label: '%s' at PC=%d\n",prog[i].str,i);
            }
        }
    }
}

/* ======================================================================== */
/* 【EXECUTION ENGINE】 */
/* ======================================================================== */

void exec(){
    int PC=0,steps=0;
    while(PC>=0&&PC<prog_len&&steps<100000000){
        Inst*i=&prog[PC];steps++;
        switch(i->op){
            case OP_UNZIP:do_unzip(i->tube[0]);break;
            case OP_HYB:do_hyb(i->tube[0]);break;
            case OP_DISPL:do_displ(i->tube[0],i->str);break;
            case OP_CLEAVE:do_cleave(i->tube[0],i->str);break;
            case OP_LIGATE:do_ligate(i->tube[0],i->tube[1],i->tube[2]);break;
            case OP_POLY:do_poly(i->tube[0],i->tube[1],i->str);break;
            case OP_MELT:do_melt(i->tube[0],i->val);break;
            case OP_ANNEAL:do_anneal(i->tube[0],i->val);break;
            case OP_FIND:do_find(i->tube[0],i->str);break;
            case OP_COUNT:do_count(i->tube[0]);break;
            case OP_SPLIT:do_split(i->tube[0],(int)i->val);break;
            case OP_MIX:do_mix(i->tube[0],i->tube[1],i->tube[2]);break;
            case OP_COPY:do_copy((int)i->tube[0],(int)i->val);break;
            case OP_BURN:do_burn(i->tube[0]);break;
            case OP_READ:
                if(i->tube[1]!=0||i->tube[2]!=0)do_read_cond(i->tube[0],i->tube[1],i->tube[2],i->imm[1],i->imm[2]);
                else do_read_tube(i->tube[0]);
                break;
            case OP_LOAD:add_s(&st[i->tube[0]],i->str);break;
            case OP_TEMP:temp=i->val;break;
            case OP_DAC:do_dac(i->tube[0],i->tube[1],(float)i->val,i->imm[0],i->imm[1]);break;
            case OP_SET:do_set(i->tube[0],i->tube[1],i->tube[2],i->imm[0],i->imm[1],i->imm[2],i->fval[2]);break;
            case OP_RST:do_rst(i->tube[0],i->tube[1],i->tube[2],i->imm[0],i->imm[1],i->imm[2],i->fval[2]);break;
            case OP_VMM:do_vmm();break;
            case OP_STDP:do_stdp(i->tube[0],i->tube[1],i->tube[2],i->imm[0],i->imm[1],i->imm[2],i->fval[2]);break;
            case OP_CHEM:do_chem(i->tube[0],i->tube[1],i->imm[0],i->imm[1],i->fval[1]);break;
            case OP_PARA:do_para((int)i->tube[0],(int)i->tube[1]);break;
            case OP_REDUCE_SUM:do_reduce_sum(i->tube[0],(int)i->tube[1],(int)i->tube[2]);break;
            case OP_REDUCE_MAX:do_reduce_max(i->tube[0],(int)i->tube[1],(int)i->tube[2]);break;
            case OP_DOT:do_dot(i->tube[0],(int)i->tube[1],(int)i->tube[2],(int)i->val);break;
            case OP_MAD:do_mad(i->tube[0],i->tube[1],i->tube[2]);break;
            case OP_LERP:do_lerp(i->tube[0],i->tube[1],i->tube[2],(float)i->val);break;
            case OP_CLAMP:do_clamp(i->tube[0],(float)i->val,(float)i->tube[1]);break;
            case OP_SIN:do_sin(i->tube[0],i->tube[1]);break;
            case OP_COS:do_cos(i->tube[0],i->tube[1]);break;
            case OP_FMA:do_fma(i->tube[0],i->tube[1],i->tube[2]);break;
            case OP_SYNC:do_sync();break;
            case OP_LABEL:break;
            case OP_JMP:PC=(int)i->val-1;break;
            case OP_JZ:if(flag_z)PC=(int)i->val-1;break;
            case OP_JNZ:if(!flag_z)PC=(int)i->val-1;break;
            case OP_JE:if(flag_e)PC=(int)i->val-1;break;
            case OP_JNE:if(!flag_e)PC=(int)i->val-1;break;
            case OP_CMP:do_cmp(i->tube[0],i->tube[1]);break;
            case OP_CALL:
                if(call_sp<CALL_STACK){call_stack[call_sp++]=PC+1;PC=(int)i->val-1;}
                break;
            case OP_RET:
                if(call_sp>0)PC=call_stack[--call_sp]-1;
                else PC=prog_len;
                break;
            case OP_SLEEP:
                if(i->val<0)do_sleep((int)st[i->tube[0]].nsm_val);
                else do_sleep((int)i->val);
                break;
            case OP_REAGENT:
                if(i->val<0)do_reagent(i->tube[0],i->tube[1]);
                else do_reagent_imm(i->tube[0],(int)i->val);
                break;
            case OP_NOP:break;
            case OP_HALT:return;
        }PC++;
    }
    if(steps>=100000000)printf("[timeout]\n");
}

void compile_dna(const char*outfile){
    FILE*f=fopen(outfile,"w");if(!f)return;
    int real_len=0;
    for(int i=0;i<prog_len;i++)if(prog[i].op!=OP_LABEL)real_len++;
    fprintf(f,"# DNAsm NSM compiled DNA\n# %d instructions (%d labels) = %d bases\n\n",real_len,n_labels,real_len*3);
    for(int i=0;i<prog_len;i++){if(prog[i].op==OP_LABEL)continue;char cd[4];enc_op(prog[i].op,cd);fprintf(f,"%s",cd);if((++real_len)%20==0)fprintf(f,"\n");else fprintf(f," ");}fprintf(f,"\n");fclose(f);
}

/* ======================================================================== */
/* 主函数 入口 */
/* ======================================================================== */

int main(int argc,char**argv){
    clock_t t0=clock();
    init_tubes();
    printf("=== DNAsm NSM -- Neural State Machine ===\n");
    printf("64x64 memristor crossbar | ISA: %d opcodes | Tubes: %d | Labels: %d max | Call depth: %d\n\n",
           N_OPS,NTUBES,MAX_LABELS,CALL_STACK);
    const char*fn=(argc>1)?argv[1]:"program.dna";
    FILE*fp=fopen(fn,"r");if(!fp){printf("Usage: ./dnasm_nsm program.dna\n");return 1;}
    char lines[1024][512];int n_lines=0;
    while(fgets(lines[n_lines],512,fp)&&n_lines<1024)n_lines++;
    fclose(fp);
    collect_labels(lines,n_lines);
    prog_len=0;
    for(int i=0;i<n_lines&&prog_len<MAX_PROG;i++){
        parse_line(lines[i],&prog[prog_len]);
        char*p=lines[i];while(*p&&isspace(*p))p++;
        if(prog[prog_len].op!=OP_NOP||(p&&*p&&*p!='\n'&&*p!='#'&&*p!=';'&&*p!='\r')){
            if(prog[prog_len].op!=OP_LABEL)prog_len++;
            else{prog[prog_len].op=OP_NOP;prog_len++;}
        }
    }
    resolve_jumps();
    printf("Loaded: %d instructions, %d labels\n",prog_len,n_labels);
    if(n_labels>0){
        printf("Labels: ");
        for(int i=0;i<n_labels&&i<10;i++)printf("%s@%d ",labels[i].name,labels[i].addr);
        if(n_labels>10)printf("...");printf("\n");
    }
    printf("DNA: ");
    for(int i=0;i<prog_len&&i<20;i++){char cd[4];enc_op(prog[i].op,cd);printf("%s ",cd);}if(prog_len>20)printf("...");printf("\n\n=== EXECUTE ===\n");
    exec();
    compile_dna("output.dna");
    printf("\n=== DONE ===\nTime: %.3fs | DNA: output.dna\n",(double)(clock()-t0)/CLOCKS_PER_SEC);
    print_reagent_summary();
    printf("NSM Energy: %.2f pJ\n",nsm_get_energy_pj(&crossbar));
    free_tubes();return 0;
}
