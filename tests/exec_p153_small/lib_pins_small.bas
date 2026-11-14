' expect: PS_PI=1 PS_R3=1 PS_P3=11 PS_R1=1 PS_P1=9 PS_X3=0 PS_SP=1 PS_SA=21 PS_SB=22 PS_SC=1 PS_IC=1 PS_IA=21 PS_IB=22
' The 8- to 20-pin PIC16F153xx parts (here the 20-pin PIC16(L)F15344, ports A, B (RB4..RB7) and C): every output and input reaches every pin of the part (DS40001889E Tables 15-1, 15-2 and 15-5 p.195-199), so Pwm, Spi and I2c accept pins of
' any port. PWM3 on RA0 (pin 0) gives RA0PPS = 0Bh and CCP1 on RB4 (pin 12) RB4PPS = 09h; RA3 stays refused (input only). Spi with SCK on RA1 (pin 1), SDO on RA2 (pin 2) and SDI on RB5 (pin 13): RA1PPS = 15h, RA2PPS = 16h. I2c with SCL on RA4
' (pin 4) and SDA on RC3 (pin 19) after SpiOff: RA4PPS = 15h, RC3PPS = 16h.
Program Ps
Device = 16F15344
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Include "pwm"
Include "spi"
Include "i2c"
Dim pi As Byte
Dim r3 As Byte
Dim p3 As Byte
Dim r1 As Byte
Dim p1 As Byte
Dim x3 As Byte
Dim sp As Byte
Dim sa As Byte
Dim sb As Byte
Dim sc As Byte
Dim ic As Byte
Dim ia As Byte
Dim ib As Byte
pi = Pwm.PwmInit(5000)
r3 = Pwm.PwmStart(3, 0, 100)
p3 = RA0PPS
r1 = Pwm.PwmStart(1, 12, 100)
p1 = RB4PPS
x3 = Pwm.PwmStart(2, 3, 100)
sp = Spi.SpiInit(100000, 0, 1, 2, 13)
sa = RA1PPS
sb = RA2PPS
Spi.SpiOff(1, 2)
sc = 1
ic = I2c.I2cInit(100000, 4, 19)
ia = RA4PPS
ib = RC3PPS
