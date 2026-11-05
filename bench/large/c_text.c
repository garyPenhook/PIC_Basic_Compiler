#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
volatile uint32_t sink;

static const uint8_t MSG[40]={72,101,108,108,111,32,80,73,67,49,56,44,32,116,104,105,115,32,105,115,32,97,32,116,101,115,116,32,111,102,32,116,101,120,116,32,119,111,114,107};
static const uint8_t NUMS[24]={49,50,51,52,53,32,45,54,55,56,32,54,53,53,51,53,32,48,32,52,50,32,55,55};
uint8_t buf[24], line_[40];
static uint32_t s;
static void PutC(uint8_t c){ LATC=c; s+=c; }
static void PutBuf(uint8_t n){ for(uint8_t i=0;i<n;i++) PutC(buf[i]); }
static uint8_t ToDec(uint32_t v){ uint8_t tmp[12],n=0; if(v==0){tmp[0]=48;n=1;} while(v>0){ tmp[n]=(uint8_t)(48+v%10); v/=10; n++; } for(uint8_t i=0;i<n;i++) buf[i]=tmp[n-1-i]; return n; }
static uint8_t ToHex(uint16_t v){ for(uint8_t i=0;i<4;i++){ uint8_t d=(uint8_t)((v>>((3-i)*4))&15); buf[i]=(d<10)?(uint8_t)(48+d):(uint8_t)(55+d);} return 4; }
static uint8_t ToBin(uint8_t v){ for(uint8_t i=0;i<8;i++){ buf[i]=(v&0x80)?49:48; v=(uint8_t)(v<<1);} return 8; }
static uint8_t ToSigned(int16_t v){ uint8_t n; if(v<0){ buf[0]=45; n=ToDec((uint32_t)(uint16_t)(0-v)); } else n=ToDec((uint32_t)v); return n; }
static uint8_t PadLeft(uint8_t n,uint8_t w){ if(n>=w) return n; for(uint8_t i=1;i<=n;i++) buf[w-i]=buf[n-i]; for(uint8_t i=0;i<w-n;i++) buf[i]=32; return w; }
static uint8_t Upper(uint8_t c){ if(c>=97&&c<=122) c-=32; return c; }
static uint8_t IsDigit(uint8_t c){ return c>=48&&c<=57; }
static void LoadMsg(void){ for(uint8_t i=0;i<40;i++) line_[i]=MSG[i]; }
static void Reverse(uint8_t n){ for(uint8_t i=0;i<(n>>1);i++){ uint8_t t=line_[i]; line_[i]=line_[n-1-i]; line_[n-1-i]=t; } }
static uint8_t CountWords(uint8_t n){ uint8_t w=0,inw=0; for(uint8_t i=0;i<n;i++){ if(line_[i]==32) inw=0; else if(!inw){ w++; inw=1; } } return w; }
static uint16_t Checksum(uint8_t n){ uint16_t a=1,b=0; for(uint8_t i=0;i<n;i++){ a=(uint16_t)((a+line_[i])%251); b=(uint16_t)((b+a)%251);} return (uint16_t)((b<<8)|a); }
static uint8_t Parse(uint8_t pos,int16_t *val){ uint8_t neg=0,c; int16_t v=0; c=NUMS[pos]; if(c==45){neg=1;pos++;} c=NUMS[pos]; while(IsDigit(c)){ v=(int16_t)(v*10+(c-48)); pos++; if(pos>=24)break; c=NUMS[pos]; } if(neg) v=(int16_t)(0-v); *val=v; return (uint8_t)(pos+1); }
static uint8_t Find(uint8_t c,uint8_t n){ uint8_t r=255; for(uint8_t i=0;i<n;i++) if(line_[i]==c){ r=i; break; } return r; }
void main(void){
  uint8_t i,n,p; int16_t v,tot; uint16_t ck;
  s=0;
  LoadMsg();
  for(i=0;i<40;i++) line_[i]=Upper(line_[i]);
  for(i=0;i<40;i++) PutC(line_[i]);
  s+=CountWords(40);
  Reverse(40);
  ck=Checksum(40);
  s+=ck;
  n=ToHex(ck); PutBuf(n);
  n=ToBin((uint8_t)(ck&255)); PutBuf(n);
  n=ToDec(s); n=PadLeft(n,12); PutBuf(n);
  p=0; tot=0;
  for(i=1;i<=6;i++){ p=Parse(p,&v); tot=(int16_t)(tot+v); n=ToSigned(v); n=PadLeft(n,8); PutBuf(n); if(p>=23)break; }
  n=ToSigned(tot); PutBuf(n);
  s+=(uint32_t)Find(82,40)+Find(81,40);
  sink=s; for(;;){}
}
