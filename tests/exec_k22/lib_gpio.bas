' expect: KG_A=0 KG_B=0 KG_C=0 KG_WPU=5 KG_RBPU=0 KG_RBPU2=128
' Port helpers on the PIC18(L)F2x/4xK22 (DS40001412H chapter 10): GpioAllDigital clears ANSELA..ANSELC (reset 1, 10.7 p.148); weak
' pull-ups exist on port B only: WPUB = the mask and INTCON2.RBPU (bit 7) cleared while a pin is selected, set again for an empty mask
' (Registers 9-2, 10-12 p.110, 152).
Program Kg
Device = 18F25K22
Clock = 64
Config FOSC = ECHPIO6, WDTEN = OFF, LVP = ON
Include "gpio"
Dim a As Byte
Dim b As Byte
Dim c As Byte
Dim wpu As Byte
Dim rbpu As Byte
Dim rbpu2 As Byte
Gpio.GpioAllDigital()
a = ANSELA
b = ANSELB
c = ANSELC
Gpio.GpioPullUps(255, 5, 255)
wpu = WPUB
rbpu = INTCON2 And 128
Gpio.GpioPullUps(0, 0, 0)
rbpu2 = INTCON2 And 128
