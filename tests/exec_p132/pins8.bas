' expect: PINS8_PA=1 PINS8_PC=0 PINS8_PB=0 PINS8_PC6=0 PINS8_RA3=0 PINS8_SA=1 PINS8_SC=0 PINS8_SB=0 PINS8_IA=1 PINS8_IC=0 PINS8_IB=0 PINS8_TX=22 PINS8_RX=1 PINS8_S2TRIS=2
' devices: 16F13214
' Pins the PIC16F132xx 8-pin part accepts for Pwm, Spi and I2c (port A only), and where Serial2 puts its pins (DS40002686B Table 3-1 p.12ff, Table 18-1 p.206, Table 18-2 p.207). A pin the part does not have makes
' the call return 0 instead of being routed to a register that does not exist; RA3 is MCLR (input only). The simulator shows no bus traffic, so only the set-up and the refusals are tested.
Program Pins8
Device = 16F13214
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Include "pwm"
Include "spi"
Include "i2c"
Include "serial2"
Dim pa As Byte
Dim pc As Byte
Dim pb As Byte
Dim pc6 As Byte
Dim ra3 As Byte
Dim sa As Byte
Dim sc As Byte
Dim sb As Byte
Dim ia As Byte
Dim ic As Byte
Dim ib As Byte
Dim tx As Byte
Dim rx As Byte
Dim s2tris As Byte
Pwm.PwmInit(1000)
pa = Pwm.PwmStart(1, 0, 100)
Pwm.PwmStop(1)
pc = Pwm.PwmStart(1, 16, 100)
Pwm.PwmStop(1)
pb = Pwm.PwmStart(1, 12, 100)
Pwm.PwmStop(1)
pc6 = Pwm.PwmStart(1, 22, 100)
Pwm.PwmStop(1)
ra3 = Pwm.PwmStart(1, 3, 100)
Pwm.PwmStop(1)
sa = Spi.SpiInit(1000000, 0, 0, 1, 2)
Spi.SpiOff(0, 1)
sc = Spi.SpiInit(1000000, 0, 16, 17, 18)
Spi.SpiOff(16, 17)
sb = Spi.SpiInit(1000000, 0, 12, 13, 14)
Spi.SpiOff(12, 13)
ia = I2c.I2cInit(100000, 0, 1)
I2c.I2cOff(0, 1)
ic = I2c.I2cInit(100000, 16, 17)
I2c.I2cOff(16, 17)
ib = I2c.I2cInit(100000, 12, 13)
I2c.I2cOff(12, 13)
Serial2.Serial2Init(9600)
tx = RA2PPS
rx = RX2PPS
s2tris = TRISA And 6
