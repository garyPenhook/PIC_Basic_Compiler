#include <xc.h>
#include <stdint.h>
#pragma config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
volatile uint32_t sink;

uint8_t data[48];
uint8_t sieve_[64];
uint16_t seed;
static uint8_t Rnd(void){ seed = (uint16_t)(seed*25u+13849u); return (uint8_t)(seed>>8); }
static void Fill(void){ for(uint8_t i=0;i<=47;i++) data[i]=Rnd(); }
static void BubbleSort(void){ for(uint8_t i=0;i<=46;i++) for(uint8_t j=0;j<=46-i;j++) if(data[j]>data[j+1]){uint8_t t=data[j];data[j]=data[j+1];data[j+1]=t;} }
static void InsertionSortDesc(void){ for(uint8_t i=1;i<=47;i++){ uint8_t k=data[i],j=i; while(j>0){ if(data[j-1]>=k)break; data[j]=data[j-1]; j--; } data[j]=k; } }
static uint8_t BinSearch(uint8_t key){ uint8_t lo=0,hi=47,r=255; while(lo<=hi){ uint8_t mid=(uint8_t)((lo+hi)>>1); if(data[mid]==key){r=mid;break;} else if(data[mid]<key) lo=mid+1; else { if(mid==0)break; hi=mid-1; } } return r; }
static uint16_t Crc16(uint8_t n){ uint16_t crc=0xFFFF; for(uint8_t i=0;i<n;i++){ crc^=(uint16_t)((uint16_t)data[i]<<8); for(uint8_t j=1;j<=8;j++) crc=(crc&0x8000)?(uint16_t)((crc<<1)^0x1021):(uint16_t)(crc<<1);} return crc; }
static uint32_t Crc32(uint8_t n){ uint32_t crc=0xFFFFFFFFul; for(uint8_t i=0;i<n;i++){ crc^=data[i]; for(uint8_t j=1;j<=8;j++) crc=(crc&1)?((crc>>1)^0xEDB88320ul):(crc>>1);} return ~crc; }
static uint8_t Sieve(void){ uint8_t cnt=0; for(uint8_t i=0;i<64;i++) sieve_[i]=1; sieve_[0]=0; sieve_[1]=0; for(uint8_t i=2;i<=7;i++) if(sieve_[i]){ uint8_t j=(uint8_t)(i*i); while(j<64){ sieve_[j]=0; j=(uint8_t)(j+i);} } for(uint8_t i=0;i<64;i++) cnt=(uint8_t)(cnt+sieve_[i]); return cnt; }
static uint16_t Gcd(uint16_t a,uint16_t b){ while(b){ uint16_t t=a%b; a=b; b=t;} return a; }
static uint16_t Isqrt(uint32_t n){ uint32_t r=0,bit=0x40000000ul; while(bit>n) bit>>=2; while(bit){ if(n>=r+bit){ n-=r+bit; r=(r>>1)+bit; } else r>>=1; bit>>=2;} return (uint16_t)r; }
static uint32_t Fib(uint8_t n){ uint32_t a=0,b=1,t; for(uint8_t i=1;i<=n;i++){ t=a+b; a=b; b=t;} return a; }
static uint16_t Collatz(uint16_t n){ uint16_t s=0; while(n!=1){ if((n&1)==0) n>>=1; else n=(uint16_t)(n*3+1); s++; } return s; }
static uint8_t Popcount(uint32_t v){ uint8_t c=0; while(v){ c=(uint8_t)(c+(v&1)); v>>=1;} return c; }
static uint8_t DigitSum(uint16_t v){ uint8_t s=0; while(v>0){ s=(uint8_t)(s+v%10); v/=10;} return s; }
void main(void){
    uint32_t s;
    seed=1234;
    Fill();
    s=Crc16(48);
    BubbleSort();
    s^=Crc32(48);
    s+=BinSearch(data[20]);
    InsertionSortDesc();
    s^=Crc16(48);
    s+=Sieve();
    s+=(uint32_t)Gcd(4620,1980)+Gcd(seed,9973);
    s+=(uint32_t)Isqrt(1000000ul)+Isqrt(s);
    s^=Fib(40);
    s+=(uint32_t)Collatz(27)+Collatz(871);
    s+=Popcount(s)+DigitSum((uint16_t)s);
    sink=s;
    for(;;){}
}
