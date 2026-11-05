' engine: sim
' expect: LPO_INIT=1 LPO_OK=1 LPO_HIOK=1 LPO_EDGESOK=1 LPO_OFF=0
' CCPxCON.OUT (bit 5) follows the pin level (DS40002043F 22.6.1 p.356, read only). MDB does not model it, so this runs in basil-sim only.
' lib_pwm.bas masks the bit; this program samples it: 5 kHz at 64 MHz, 401 of 800 steps (about 50 %), so over many
' periods the samples must be high about half of the time and must change many times. With the module disabled OUT is 0.
Program Lpo
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pwm"
Dim init As Byte
Dim ok As Byte
Dim hi As Word
Dim n As Word
Dim last As Byte
Dim cur As Byte
Dim edges As Word
Dim hiok As Byte
Dim edgesok As Byte
Dim off As Byte
init = Pwm.PwmInit(5000)
ok = Pwm.PwmStart(1, 18, 401)
hi = 0
edges = 0
last = CCP1CON And 32
For n = 1 To 3000
    cur = CCP1CON And 32
    If cur <> 0 Then
        hi = hi + 1
    End If
    If cur <> last Then
        edges = edges + 1
    End If
    last = cur
Next
hiok = 0
If hi > 1200 Then
    If hi < 1800 Then
        hiok = 1
    End If
End If
edgesok = 0
If edges >= 10 Then
    edgesok = 1
End If
CCP1CON = 0
off = CCP1CON And 32
