#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
volatile uint32_t sink;

static const uint8_t CMDS[32]={1,5,10,2,3,200,4,0,1,7,33,2,1,4,99,3,9,8,2,250,5,6,1,3,200,9,1,2,77,4,4,0};
uint8_t ring[16],head,tail,cnt,ma[16],mb[16],rle[48],src[32],dst[32],regs[8],state,mode; uint16_t mc[16],accum;
static void Push(uint8_t b){ if(cnt<16){ ring[head]=b; head=(head+1)&15; cnt++; } }
static uint8_t Pop(void){ uint8_t r=0; if(cnt>0){ r=ring[tail]; tail=(tail+1)&15; cnt--; } return r; }
static void MatMul(void){ for(uint8_t i=0;i<4;i++) for(uint8_t j=0;j<4;j++){ uint16_t s=0; for(uint8_t k=0;k<4;k++) s=(uint16_t)(s+ma[i*4+k]*mb[k*4+j]); mc[i*4+j]=s; } }
static void InitMat(void){ for(uint8_t i=0;i<16;i++){ ma[i]=(uint8_t)(i*3+1); mb[i]=(uint8_t)(17-i);} }
static uint16_t Trace(void){ uint16_t t=0; for(uint8_t i=0;i<4;i++) t=(uint16_t)(t+mc[i*5]); return t; }
static uint8_t Encode(uint8_t n){ uint8_t i=0,o=0,run,cur; while(i<n){ cur=src[i]; run=1; while(i+run<n){ if(src[i+run]!=cur)break; if(run==255)break; run++; } rle[o]=run; rle[o+1]=cur; o+=2; i=(uint8_t)(i+run);} return o; }
static uint8_t Decode(uint8_t n){ uint8_t i=0,o=0; while(i<n){ for(uint8_t k=1;k<=rle[i];k++){ dst[o]=rle[i+1]; o++; } i+=2; } return o; }
static void MakeSrc(void){ uint8_t v=3; for(uint8_t i=0;i<32;i++){ if((i&7)==0) v+=5; if((i&3)==3) v+=1; src[i]=v; } }
static void Exec(uint8_t op,uint8_t a){ switch(op){ case 1: regs[a&7]++; break; case 2: regs[a&7]--; break; case 3: regs[0]=regs[a&7]; break; case 4: regs[a&7]=regs[0]; break; case 5: regs[0]+=a; break; case 6: regs[0]^=a; break; case 7: regs[0]<<=1; break; case 8: regs[0]>>=1; break; default: accum+=a; } }
static void Machine(uint8_t b){ switch(state){ case 0: if(b==1) state=1; else if(b==2) state=3; break; case 1: mode=b; state=2; break; case 2: Exec(mode,b); state=0; break; case 3: accum+=b; state=(b>100)?0:4; break; case 4: accum^=b; state=0; break; default: state=0; } }
static uint16_t Fletcher(uint8_t n){ uint16_t a=0,b=0; for(uint8_t i=0;i<n;i++){ a=(uint16_t)((a+dst[i])%255); b=(uint16_t)((b+a)%255);} return (uint16_t)((b<<8)|a); }
static uint8_t ParityByte(uint8_t v){ v^=v>>4; v^=v>>2; v^=v>>1; return v&1; }
static uint8_t RevBits(uint8_t v){ uint8_t r=0; for(uint8_t i=0;i<8;i++){ r=(uint8_t)((r<<1)|(v&1)); v>>=1;} return r; }
static void ShiftOut(uint8_t v){ for(uint8_t i=0;i<8;i++){ if(v&0x80) LATB|=1; else LATB&=0xFE; LATB|=2; LATB&=0xFD; v=(uint8_t)(v<<1);} }
void main(void){
  uint8_t i,n,m; uint16_t w; uint32_t s;
  state=0;
  for(i=0;i<32;i++){ Push(CMDS[i]); if(cnt>12){ while(cnt>4) Machine(Pop()); } }
  while(cnt>0) Machine(Pop());
  s=accum;
  for(i=0;i<8;i++){ s+=regs[i]; ShiftOut(regs[i]); }
  InitMat(); MatMul(); s+=Trace();
  MakeSrc(); n=Encode(32); m=Decode(n); w=Fletcher(m); s+=(uint32_t)w+n+m;
  for(i=0;i<32;i++) s+=(uint32_t)ParityByte(dst[i])+RevBits(dst[i]);
  sink=s; for(;;){}
}
