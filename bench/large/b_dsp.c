#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
volatile int32_t sink;

static const int16_t SINT[18]={0,1143,2275,3384,4458,5486,6455,7358,8182,8923,9573,10126,10580,10929,11172,11307,11345,11245};
int16_t samples[32]; static const int16_t coef[8]={3,11,25,41,41,25,11,3}; int16_t hist[8];
int16_t pidI,pidPrev; uint16_t lcg;
static int16_t Sine(uint8_t a){ uint8_t q=a>>6, idx=(a&63)>>2, frac=a&3; int16_t v,d;
  if(q&1){ idx=16-idx; frac=4-frac; if(frac==4){frac=0; idx--;} frac=4-frac; if(frac==4) frac=0; }
  v=SINT[idx]; d=SINT[idx+1]-v; v=(int16_t)(v+(d*frac)/4); if(q>=2) v=-v; return v; }
static void Gen(void){ for(uint8_t i=0;i<32;i++){ lcg=(uint16_t)(lcg*5+1); samples[i]=(int16_t)(Sine((uint8_t)(i*8))+(lcg>>12)-8);} }
static int16_t Fir(int16_t x){ for(uint8_t i=7;i>=1;i--) hist[i]=hist[i-1]; hist[0]=x; int32_t acc=0; for(uint8_t i=0;i<8;i++) acc+=(int32_t)hist[i]*coef[i]; return (int16_t)(acc/160); }
static int16_t Pid(int16_t sp,int16_t pv){ int16_t e=sp-pv,p,d,out; pidI=pidI+e/8; if(pidI>2000)pidI=2000; if(pidI<-2000)pidI=-2000; p=e*3; d=(e-pidPrev)*2; pidPrev=e; out=p+pidI+d; if(out>4095)out=4095; if(out<-4095)out=-4095; return out; }
static int16_t Mean(void){ int32_t acc=0; for(uint8_t i=0;i<32;i++) acc+=samples[i]; return (int16_t)(acc/32); }
static uint16_t Rms(void){ uint32_t acc=0,r=0,b=0x40000000ul; for(uint8_t i=0;i<32;i++){ int16_t v=samples[i]; if(v<0)v=-v; acc+=(uint32_t)((int32_t)v*v);} acc/=32; while(b>acc) b>>=2; while(b){ if(acc>=r+b){acc-=r+b; r=(r>>1)+b;} else r>>=1; b>>=2;} return (uint16_t)r; }
static int16_t MinMax(void){ int16_t lo=samples[0],hi=samples[0]; for(uint8_t i=1;i<32;i++){ if(samples[i]<lo)lo=samples[i]; if(samples[i]>hi)hi=samples[i]; } return (int16_t)(hi-lo); }
static int16_t MulQ15(int16_t a,int16_t b){ int32_t p=a; p=p*b; return (int16_t)(p>>15); }
static uint16_t Scale(uint16_t v,uint16_t num,uint16_t den){ uint32_t t=v; t=t*num; return (uint16_t)(t/den); }
static int16_t Lowpass(int16_t x,int16_t y){ return (int16_t)(y+(x-y)/8); }
void main(void){
  int16_t f,y=0,u,plant=0; int32_t s=0;
  lcg=77; Gen();
  for(uint8_t i=0;i<32;i++){ f=Fir(samples[i]); y=Lowpass(samples[i],y); u=Pid(1000,plant); plant=(int16_t)(plant+(u-plant)/16); s=s+f+y+plant; }
  s^=Mean(); s+=Rms(); s+=MinMax();
  s+=MulQ15(12345,-9876); s+=Scale(1000,3,7); s+=Scale(65000,255,1000);
  sink=s; for(;;){}
}
