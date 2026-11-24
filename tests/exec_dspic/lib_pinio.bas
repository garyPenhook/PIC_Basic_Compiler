' expect: P_OK1=1 P_OK2=0 P_OK3=1 P_OK4=0 P_OK5=1 P_LB=4 P_TB=65530 P_G1=1 P_G2=0 P_PW=165 P_PR=165 P_PUB=33 P_ODC=16 P_ANB=0 P_DONE=1
Program P
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "pinio"
Include "gpio"
Dim OK1 As Byte
Dim OK2 As Byte
Dim OK3 As Byte
Dim OK4 As Byte
Dim OK5 As Byte
Dim LB As Word
Dim TB As Word
Dim G1 As Byte
Dim G2 As Byte
Dim PW As Byte
Dim PR As Byte
Dim PUB As Word
Dim ODC As Word
Dim ANB As Word
Dim DONE As Byte
OK1 = 0
OK2 = 0
OK3 = 0
OK4 = 0
OK5 = 0
If Pinio.PinOk(16) Then
    OK1 = 1
End If
If Pinio.PinOk(5) Then
    OK2 = 1
End If
If Pinio.PinOk(31) Then
    OK3 = 1
End If
If Pinio.PinOk(51) Then
    OK4 = 1
End If
If Pinio.PinOk(49) Then
    OK5 = 1
End If
Pinio.PinOutput(18)
Pinio.PinSet(18, True)
LB = LATB
Pinio.PinInput(26)
Pinio.PinOutput(16)
TB = TRISB
Pinio.PinSet(16, False)
G1 = 0
G2 = 0
Pinio.PinInput(17)
If Pinio.PinGet(18) Then
    G1 = 1
End If
Pinio.PortDigital(16)
Pinio.PortDirection(16, False)
Pinio.PortWrite(16, $A5)
PW = Byte(LATB)
PR = Pinio.PortRead(16)
Gpio.GpioAllDigital()
Gpio.GpioPullUps(0, 33, 0)
Gpio.GpioOpenDrain(0, 0, 16)
PUB = CNPUB
ODC = ODCC
ANB = ANSELB
DONE = 1
