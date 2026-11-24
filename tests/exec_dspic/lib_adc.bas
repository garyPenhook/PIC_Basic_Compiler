' expect: A_CON1L=32768 A_CON1H=96 A_CON2L=1 A_CON2H=2 A_CON3H=128 A_CON5H=1536 A_RDY=1 A_ANSB=1 A_DONE=1
' Library adc on the dsPIC33CK: AdcInit register values (12-bit integer, SHRADCS = 1, SHRSAMC = 2 at 8 MHz, WARMTIME = 6, SHREN), SHRRDY, AdcPin(2) sets ANSELB.7 (AN2 is RB7); the simulator does not model a conversion, so AdcRead, AdcReadAvg, AdcMillivolts and ADin (also the internal channels) only have to run to the end through their time-out.
Program A
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW
Include "adc"
Dim CON1L As Word
Dim CON1H As Word
Dim CON2L As Word
Dim CON2H As Word
Dim CON3H As Word
Dim CON5H As Word
Dim RDY As Byte
Dim ANSB As Byte
Dim V As Word
Dim DONE As Byte
Adc.AdcInit()
Adc.AdcPin(2)
V = Adc.AdcRead(2)
CON1L = ADCON1L
CON1H = ADCON1H
CON2L = ADCON2L
CON2H = ADCON2H
CON3H = ADCON3H
CON5H = ADCON5H
RDY = 0
If ADCON5L.15 = 1 Then
    RDY = 1
End If
ANSB = 0
If ANSELB.7 = 1 Then
    ANSB = 1
End If
V = Adc.AdcReadAvg(Adc.AdcChTemp, 4)
V = Adc.AdcMillivolts(V, 3300)
V = Adc.ADin(Adc.AdcChBandGap)
V = Adc.ADin(7)
DONE = 1
