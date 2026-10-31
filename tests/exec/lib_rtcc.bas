' expect: LR_NOINIT=4 LR_SET5=5 LR_AL5=5 LR_SQ5=5 LR_TR5=5 LR_RAM5=5 LR_EE5=5 LR_ID5=5 LR_BUS=1 LR_VAL=77
Program Lr
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "i2c"
Include "rtcc"
Dim noinit As Byte
Dim set5 As Byte
Dim al5 As Byte
Dim sq5 As Byte
Dim tr5 As Byte
Dim ram5 As Byte
Dim ee5 As Byte
Dim id5 As Byte
Dim bus As Byte
Dim val As Byte
Dim ok As Byte
Dim fl As Boolean
val = 77
' I2c not initialised: every bus routine answers 4 and leaves the outputs alone.
noinit = Rtcc.RtccRead()
' Bad arguments are refused before anything is sent: 5, whatever the bus state.
set5 = Rtcc.RtccSet(24, 2, 30, 1, 0, 0, 0)
al5 = Rtcc.RtccAlarm(2, 0, 1, 1, 1, 0, 0, 0)
sq5 = Rtcc.RtccSquareWave(4)
tr5 = Rtcc.RtccTrim(200, False)
ram5 = Rtcc.RtccRamRead(64, val)
ee5 = Rtcc.RtccEeRead(128, val)
id5 = Rtcc.RtccIdRead(8, val)
' Bus set up, nothing on it (the simulator has no pull-ups): a failure in bounded time, outputs untouched.
ok = I2c.I2cInit(100000, 19, 20)
bus = Rtcc.RtccAlarmFlag(0, fl)
If bus <> 0 Then
    bus = 1
End If
