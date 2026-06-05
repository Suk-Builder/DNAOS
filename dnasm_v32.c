/* DNAsm v3.2 -- DNA Native ISA + GPU Parallel + Control Flow
 *
 * ISA: 51 opcodes
 *   v1: Molecular (UNZIP/HYB/DISPL/CLEAVE/LIGATE/POLY/MELT/ANNEAL/FIND/COUNT/SPLIT/MIX)
 *   v2: I/O (COPY/BURN/READ/LOAD/TEMP)
 *   v3: Numerical (NUM/ADD/PRINT/SUB/MUL/DIV/FIB/PRIME/FACT/POW/SQRT/GCD/LN)
 *   v3.1: GPU Parallel (PARA/REDUCE_SUM/REDUCE_MAX/DOT/MAD/LERP/CLAMP/SIN/COS/FMA/SYNC)
 *   v3.2: Control Flow (LABEL/JMP/JZ/JNZ/JE/JNE/CMP/CALL/RET)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <time.h>

#define MAX_STRANDS 10000
#define MAX_LEN     256
#define NTUBES      64
#define MAX_PROG    4096
#define NUM_PHYSICAL_LIMIT 500
#define VAL_SEQ     "ACGTACGTACGTACGT"
#define MAX_LABELS  256
#define CALL_STACK  64

enum {
    OP_UNZIP=0, OP_HYB,  OP_DISPL, OP_CLEAVE,
    OP_LIGATE,  OP_POLY, OP_MELT,  OP_ANNEAL,
    OP_FIND,    OP_COUNT,OP_SPLIT, OP_MIX,
    OP_COPY,    OP_BURN, OP_READ,  OP_LOAD,
    OP_TEMP,    OP_NOP,  OP_HALT,  OP_NUM,
    OP_ADD,     OP_PRINT,OP_SUB,   OP_MUL,
    OP_DIV,     OP_FIB,  OP_PRIME, OP_FACT,
    OP_POW,     OP_SQRT, OP_GCD,   OP_LN,
    /* ---- GPU Parallel Primitives v3.1 ---- */
    OP_PARA,    OP_REDUCE_SUM, OP_REDUCE_MAX,
    OP_DOT,     OP_MAD,  OP_LERP,  OP_CLAMP,
    OP_SIN,     OP_COS,  OP_FMA,   OP_SYNC,
    /* ---- Control Flow v3.2 ---- */
    OP_LABEL,   /* LABEL name -- define label (no-op at runtime) */
    OP_JMP,     /* JMP label -- unconditional jump */
    OP_JZ,      /* JZ label -- jump if st[0] == 0 */
    OP_JNZ,     /* JNZ label -- jump if st[0] != 0 */
    OP_JE,      /* JE label -- jump if equal (after CMP) */
    OP_JNE,     /* JNE label -- jump if not equal (after CMP) */
    OP_CMP,     /* CMP st[a] st[b] -- compare, set flags */
    OP_CALL,    /* CALL label -- call subroutine */
    OP_RET,     /* RET -- return from subroutine */
    N_OPS
};
const char*op_name[]={
    "UNZIP","HYB","DISPL","CLEAVE","LIGATE","POLY","MELT","ANNEAL",
    "FIND","COUNT","SPLIT","MIX","COPY","BURN","READ","LOAD",
    "TEMP","NOP","HALT","NUM","ADD","PRINT","SUB","MUL",
    "DIV","FIB","PRIME","FACT","POW","SQRT","GCD","LN",
    "PARA","REDUCE_SUM","REDUCE_MAX","DOT","MAD","LERP","CLAMP",
    "SIN","COS","FMA","SYNC",
    "LABEL","JMP","JZ","JNZ","JE","JNE","CMP","CALL","RET"
};

int b2d(char c){switch(c){case'A':case'a':return 0;case'T':case't':return 1;case'C':case'c':return 2;case'G':case'g':return 3;}return 0;}
char d2b(int d){return"ATCG"[d&3];}
void enc_op(int op,char o[4]){o[0]=d2b(op/16);o[1]=d2b((op/4)%4);o[2]=d2b(op%4);o[3]=0;}
int dec_op(const char c[3]){int cd=b2d(c[0])*16+b2d(c[1])*4+b2d(c[2]);return(cd<N_OPS)?cd:OP_NOP;}

typedef struct{char seq[MAX_LEN];int len;}Strand;
typedef struct{Strand*s;int n,cap;long long num_val;}Tube;
Tube st[NTUBES],dt[NTUBES];
double temp=37.0;

/* ---- Control Flow v3.2 ---- */
typedef struct{char name[32];int addr;}Label;
static Label labels[MAX_LABELS];static int n_labels=0;
static int call_stack[CALL_STACK];static int call_sp=0;
static int flag_z=0,flag_e=0,flag_g=0,flag_l=0; /* Z=zero E=equal G=greater L=less */

void init_tubes(){
    for(int i=0;i<NTUBES;i++){
        st[i].s=(Strand*)malloc(MAX_STRANDS*sizeof(Strand));
        st[i].n=0;st[i].cap=MAX_STRANDS;st[i].num_val=0;
        dt[i].s=(Strand*)malloc(MAX_STRANDS*sizeof(Strand));
        dt[i].n=0;dt[i].cap=MAX_STRANDS;dt[i].num_val=0;
    }
    n_labels=0;call_sp=0;flag_z=flag_e=flag_g=flag_l=0;
}
void free_tubes(){for(int i=0;i<NTUBES;i++){free(st[i].s);free(dt[i].s);}}
void clear_t(Tube*t){t->n=0;t->num_val=0;}

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
    t->num_val=N;
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
void do_read(int idx){Tube*t=&st[idx];printf("  READ st[%d]: %d strands [num=%lld]\n",idx,t->n,t->num_val);for(int i=0;i<t->n&&i<3;i++)printf("    [%d] %s (len=%d)\n",i,t->s[i].seq,t->s[i].len);if(t->n>3)printf("    ... (%d more)\n",t->n-3);}
void do_burn(int idx){clear_t(&st[idx]);clear_t(&dt[idx]);}

/* ---- Numerical Instructions v3 ---- */
void do_num(int idx,long long N){clear_t(&st[idx]);add_n(&st[idx],N);}
void do_add(int dst,int src){st[dst].num_val += st[src].num_val;}
void do_sub(int dst,int src){st[dst].num_val -= st[src].num_val;if(st[dst].num_val<0)st[dst].num_val=0;}
void do_mul(int dst,int src){st[dst].num_val *= st[src].num_val;}
void do_div(int dst,int src){if(st[src].num_val!=0)st[dst].num_val /= st[src].num_val;}
void do_pow(int idx,int e){long long b=st[idx].num_val,r=1;for(int i=0;i<e;i++)r*=b;st[idx].num_val=r;}
void do_fib(int idx,int N){long long a=0,b=1,t;for(int i=0;i<N;i++){t=a+b;a=b;b=t;}st[idx].num_val=a;}
void do_fact(int idx,int N){long long r=1;for(int i=2;i<=N;i++)r*=i;st[idx].num_val=r;}
void do_prime(int idx,int N){int cnt=0;for(int i=2;i<=N;i++){int is_p=1;for(int j=2;j*j<=i;j++)if(i%j==0){is_p=0;break;}if(is_p)cnt++;}st[idx].num_val=cnt;}
void do_sqrt(int idx){long long v=st[idx].num_val;long long r=0;while(r*r<=v)r++;st[idx].num_val=r-1;}
void do_gcd(int a,int b){long long x=st[a].num_val,y=st[b].num_val;while(y){long long t=y;y=x%y;x=t;}st[a].num_val=x;}
void do_ln(int idx){long long v=st[idx].num_val;double r=0;for(int i=1;i<=1000000;i*=2){if(i<=v)r+=0.693;}st[idx].num_val=(long long)(r*1000);}
void do_copy(int idx,int cycles){Tube*t=&st[idx];for(int c=0;c<cycles&&t->n<t->cap/2;c++){int cur=t->n;for(int i=0;i<cur&&t->n<t->cap;i++){char rc[MAX_LEN];revcomp(t->s[i].seq,rc);add_s(t,rc);}}if(t->num_val>0){int mult=1<<cycles;t->num_val*=mult;}}
void do_print(int idx){printf("  [st[%d]] = %lld\n",idx,st[idx].num_val);}

/* ---- GPU Parallel Primitives v3.1 ---- */
static int warp_start=0,warp_end=0;
void do_para(int start,int end){warp_start=start&63;warp_end=(end>63?63:end)&63;}
void do_reduce_sum(int dst,int start,int end){
    long long sum=0;int s=start&63,e=(end>63?63:end)&63;
    for(int i=s;i<=e;i++)sum+=st[i].num_val;
    st[dst&63].num_val=sum;
}
void do_reduce_max(int dst,int start,int end){
    long long mx=-9223372036854775807LL;int s=start&63,e=(end>63?63:end)&63;
    for(int i=s;i<=e;i++)if(st[i].num_val>mx)mx=st[i].num_val;
    st[dst&63].num_val=mx;
}
void do_dot(int dst,int a_start,int b_start,int N){
    long long sum=0;int a=a_start&63,b=b_start&63;
    for(int i=0;i<N&&i<64;i++)sum+=st[(a+i)&63].num_val*st[(b+i)&63].num_val;
    st[dst&63].num_val=sum;
}
void do_mad(int dst,int a,int b){int d=dst&63,A=a&63,B=b&63;st[d].num_val=st[A].num_val*st[B].num_val+st[d].num_val;}
void do_lerp(int dst,int a,int b,long long t){
    int d=dst&63,A=a&63,B=b&63;
    st[d].num_val=(st[A].num_val*(1000-t)+st[B].num_val*t)/1000;
}
void do_clamp(int dst,long long mn,long long mx){int d=dst&63;if(st[d].num_val<mn)st[d].num_val=mn;if(st[d].num_val>mx)st[d].num_val=mx;}
void do_sin(int dst,int src){double x=st[src&63].num_val*0.001;st[dst&63].num_val=(long long)(sin(x)*1000);}
void do_cos(int dst,int src){double x=st[src&63].num_val*0.001;st[dst&63].num_val=(long long)(cos(x)*1000);}
void do_fma(int dst,int a,int b){int d=dst&63,A=a&63,B=b&63;st[d].num_val=st[A].num_val*st[B].num_val+st[d].num_val;}
void do_sync(void){}

/* ---- Control Flow v3.2 ---- */
void do_cmp(int a,int b){
    long long va=st[a&63].num_val,vb=st[b&63].num_val;
    flag_z=(va==0);flag_e=(va==vb);flag_g=(va>vb);flag_l=(va<vb);
}
int find_label(const char*name){
    for(int i=0;i<n_labels;i++)if(strcasecmp(labels[i].name,name)==0)return labels[i].addr;
    return -1;
}

/* ---- Program ---- */
typedef struct{int op;int tube[3];double val;char str[64];}Inst;
Inst prog[MAX_PROG];int prog_len=0;

void parse_line(const char*line,Inst*I){
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
    
    /* LABEL name -- no params needed */
    if(I->op==OP_LABEL&&nt>=2){
        strncpy(I->str,tok[1],63);I->str[63]=0;
    }
    /* JMP/JZ/JNZ/JE/JNE/CALL label -- store label name in str */
    else if((I->op==OP_JMP||I->op==OP_JZ||I->op==OP_JNZ||I->op==OP_JE||I->op==OP_JNE||I->op==OP_CALL)&&nt>=2){
        strncpy(I->str,tok[1],63);I->str[63]=0;
    }
    /* RET -- no params */
    else if(I->op==OP_RET){
        /* nothing */
    }
    /* CMP st[a] st[b] */
    else if(I->op==OP_CMP&&nt>=3){
        char*tk=tok[1];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[0]=atoi(q)&63;}
        else I->tube[0]=atoi(tk)&63;
        tk=tok[2];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[1]=atoi(q)&63;}
        else I->tube[1]=atoi(tk)&63;
    }
    /* v3 numerical ops: OPCODE st[k] N */
    else if((I->op==OP_NUM||I->op==OP_FIB||I->op==OP_PRIME||I->op==OP_FACT||I->op==OP_POW||I->op==OP_COPY)&&nt>=3){
        char*tk=tok[1];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[0]=atoi(q)&63;}
        else{I->tube[0]=atoi(tk)&63;}
        I->val=atoll(tok[2]);
    }
    /* GPU parallel ops: PARA st[start] st[end] */
    else if(I->op==OP_PARA&&nt>=3){
        for(int i=1;i<nt&&i<=2;i++){
            char*tk=tok[i];
            if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[i-1]=atoi(q)&63;}
            else I->tube[i-1]=atoi(tk)&63;
        }
    }
    /* GPU reduce ops */
    else if((I->op==OP_REDUCE_SUM||I->op==OP_REDUCE_MAX)&&nt>=4){
        for(int i=1;i<nt&&i<=3;i++){
            char*tk=tok[i];
            if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[i-1]=atoi(q)&63;}
            else I->tube[i-1]=atoi(tk)&63;
        }
    }
    /* GPU dot */
    else if(I->op==OP_DOT&&nt>=5){
        char*tk=tok[1];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[0]=atoi(q)&63;}
        else I->tube[0]=atoi(tk)&63;
        tk=tok[2];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[1]=atoi(q)&63;}
        else I->tube[1]=atoi(tk)&63;
        tk=tok[3];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[2]=atoi(q)&63;}
        else I->tube[2]=atoi(tk)&63;
        I->val=atoll(tok[4]);
    }
    /* GPU MAD/FMA */
    else if((I->op==OP_MAD||I->op==OP_FMA)&&nt>=4){
        for(int i=1;i<nt&&i<=3;i++){
            char*tk=tok[i];
            if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[i-1]=atoi(q)&63;}
            else I->tube[i-1]=atoi(tk)&63;
        }
    }
    /* GPU LERP */
    else if(I->op==OP_LERP&&nt>=5){
        char*tk=tok[1];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[0]=atoi(q)&63;}
        else I->tube[0]=atoi(tk)&63;
        tk=tok[2];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[1]=atoi(q)&63;}
        else I->tube[1]=atoi(tk)&63;
        tk=tok[3];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[2]=atoi(q)&63;}
        else I->tube[2]=atoi(tk)&63;
        I->val=atoll(tok[4]);
    }
    /* GPU CLAMP */
    else if(I->op==OP_CLAMP&&nt>=4){
        char*tk=tok[1];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[0]=atoi(q)&63;}
        else I->tube[0]=atoi(tk)&63;
        I->val=atoll(tok[2]);
        I->tube[1]=atoll(tok[3]);
    }
    /* GPU SIN/COS */
    else if((I->op==OP_SIN||I->op==OP_COS)&&nt>=3){
        char*tk=tok[1];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[0]=atoi(q)&63;}
        else I->tube[0]=atoi(tk)&63;
        tk=tok[2];
        if((tk[0]=='s'||tk[0]=='S')&&(tk[1]=='t'||tk[1]=='T')){char*q=tk+2;if(*q=='[')q++;I->tube[1]=atoi(q)&63;}
        else I->tube[1]=atoi(tk)&63;
    }
    /* Generic */
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

/* Two-pass load: pass 1 collects labels, pass 2 resolves jumps */
void collect_labels(char lines[][512],int n_lines){
    n_labels=0;prog_len=0;
    Inst tmp;
    for(int i=0;i<n_lines;i++){
        parse_line(lines[i],&tmp);
        char*p=lines[i];while(*p&&isspace(*p))p++;
        if(tmp.op==OP_LABEL&&tmp.str[0]){
            if(n_labels<MAX_LABELS){
                strncpy(labels[n_labels].name,tmp.str,31);labels[n_labels].name[31]=0;
                labels[n_labels].addr=prog_len; /* LABEL's own PC */
                n_labels++;
            }
        }
        if(tmp.op!=OP_NOP||(p&&*p&&*p!='\n'&&*p!='#'&&*p!=';'&&*p!='\r')){
            prog_len++; /* ALL lines with content count toward PC */
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
            case OP_COPY:do_copy((int)i->tube[0],(int)i->val);break;
            case OP_BURN:do_burn(i->tube[0]);break;
            case OP_READ:do_read(i->tube[0]);break;
            case OP_LOAD:add_s(&st[i->tube[0]],i->str);break;
            case OP_TEMP:temp=i->val;break;
            case OP_NUM:do_num((int)i->tube[0],(long long)i->val);break;
            case OP_ADD:do_add(i->tube[0],i->tube[1]);break;
            case OP_SUB:do_sub(i->tube[0],i->tube[1]);break;
            case OP_MUL:do_mul(i->tube[0],i->tube[1]);break;
            case OP_DIV:do_div(i->tube[0],i->tube[1]);break;
            case OP_FIB:do_fib((int)i->tube[0],(int)i->val);break;
            case OP_PRIME:do_prime((int)i->tube[0],(int)i->val);break;
            case OP_FACT:do_fact((int)i->tube[0],(int)i->val);break;
            case OP_POW:do_pow(i->tube[0],(int)i->val);break;
            case OP_SQRT:do_sqrt(i->tube[0]);break;
            case OP_GCD:do_gcd(i->tube[0],i->tube[1]);break;
            case OP_LN:do_ln(i->tube[0]);break;
            case OP_PRINT:do_print(i->tube[0]);break;
            /* GPU v3.1 */
            case OP_PARA:do_para((int)i->tube[0],(int)i->tube[1]);break;
            case OP_REDUCE_SUM:do_reduce_sum(i->tube[0],(int)i->tube[1],(int)i->val);break;
            case OP_REDUCE_MAX:do_reduce_max(i->tube[0],(int)i->tube[1],(int)i->val);break;
            case OP_DOT:do_dot(i->tube[0],(int)i->tube[1],(int)i->tube[2],(int)i->val);break;
            case OP_MAD:do_mad(i->tube[0],i->tube[1],(int)i->val);break;
            case OP_LERP:do_lerp(i->tube[0],i->tube[1],i->tube[2],(long long)i->val);break;
            case OP_CLAMP:do_clamp(i->tube[0],(long long)i->val,(long long)i->tube[1]);break;
            case OP_SIN:do_sin(i->tube[0],i->tube[1]);break;
            case OP_COS:do_cos(i->tube[0],i->tube[1]);break;
            case OP_FMA:do_fma(i->tube[0],i->tube[1],(int)i->val);break;
            case OP_SYNC:do_sync();break;
            /* Control Flow v3.2 */
            case OP_LABEL:break; /* no-op at runtime */
            case OP_JMP:PC=(int)i->val-1;break; /* -1 because PC++ after switch */
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
                else PC=prog_len; /* return from main = halt */
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
    fprintf(f,"# DNAsm v3.2 compiled DNA\n# %d instructions (%d labels) = %d bases\n\n",real_len,n_labels,real_len*3);
    for(int i=0;i<prog_len;i++){if(prog[i].op==OP_LABEL)continue;char cd[4];enc_op(prog[i].op,cd);fprintf(f,"%s",cd);if((++real_len)%20==0)fprintf(f,"\n");else fprintf(f," ");}fprintf(f,"\n");fclose(f);
}

int main(int argc,char**argv){
    clock_t t0=clock();
    init_tubes();
    printf("=== DNAsm v3.2 -- DNA Native ISA + GPU + Control Flow ===\n");
    printf("ISA: %d opcodes | Tubes: %d | Labels: %d max | Call depth: %d\n\n",N_OPS,NTUBES,MAX_LABELS,CALL_STACK);
    const char*fn=(argc>1)?argv[1]:"program.dna";
    FILE*fp=fopen(fn,"r");if(!fp){printf("Usage: ./dnasm3 program.dna\n");return 1;}
    char lines[1024][512];int n_lines=0;
    while(fgets(lines[n_lines],512,fp)&&n_lines<1024)n_lines++;
    fclose(fp);
    /* Pass 1: collect labels */
    collect_labels(lines,n_lines);
    /* Pass 2: parse instructions */
    prog_len=0;
    for(int i=0;i<n_lines&&prog_len<MAX_PROG;i++){
        parse_line(lines[i],&prog[prog_len]);
        char*p=lines[i];while(*p&&isspace(*p))p++;
        if(prog[prog_len].op!=OP_NOP||(p&&*p&&*p!='\n'&&*p!='#'&&*p!=';'&&*p!='\r')){
            if(prog[prog_len].op!=OP_LABEL)prog_len++;
            else{prog[prog_len].op=OP_NOP;prog_len++;} /* LABEL -> NOP, occupies slot */
        }
    }
    /* Resolve label addresses */
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
    free_tubes();return 0;
}
