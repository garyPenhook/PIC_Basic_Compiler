' expect: KS_I1=1 KS_A=165 KS_B=60 KS_ST=0 KS_C1=32 KS_I2=1 KS_C=129 KS_C1B=42 KS_I3=1 KS_D=66 KS_C2=32 KS_BAD=0
' stim: lib_spi.stim.toml
' SPI library on the PIC18(L)F2x/4xK22 (DS40001412H chapter 15): MSSP1 on its fixed pins SCK = RC3 (19), SDO = RC5 (21), SDI = RC4 (20),
' then MSSP2 on SCK = RB1 (9), SDO = RB3 (11), SDI = RB2 (10) of the 28-pin parts. Mode 0 at FOSC / 4 (16 MHz at 64 MHz): SSP1CON1 =
' SSPEN | SSPM 0000 = 32; mode 1 at 1 MHz: SSPM 1010 with CKP 0 = 42, and the erratum 13.1 wait after each byte (CKE = 0). Pins of
' neither module are refused.
Program Ks
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "spi"
Dim i1 As Byte
Dim a As Byte
Dim b As Byte
Dim st As Byte
Dim c1 As Byte
Dim i2 As Byte
Dim c As Byte
Dim c1b As Byte
Dim i3 As Byte
Dim d As Byte
Dim c2 As Byte
Dim bad As Byte
i1 = Spi.SpiInit(16000000, 0, 19, 21, 20)
c1 = SSP1CON1
a = Spi.SpiTransfer(1)
b = Spi.SpiTransfer(2)
st = Spi.SpiStatus()
Spi.SpiOff(19, 21)
i2 = Spi.SpiInit(1000000, 1, 19, 21, 20)
c1b = SSP1CON1
c = Spi.SpiRead()
Spi.SpiOff(19, 21)
i3 = Spi.SpiInit(1000000, 0, 9, 11, 10)
c2 = SSP2CON1 And 32
d = Spi.SpiTransfer(7)
Spi.SpiOff(9, 11)
bad = Spi.SpiInit(1000000, 0, 9, 21, 20)
