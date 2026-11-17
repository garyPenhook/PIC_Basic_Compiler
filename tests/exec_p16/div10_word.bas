' Exhaustive Word /10: reference quotient/remainder advance as decimal counters.
' expect: T_ERRORS=0 T_CHECKED=65536
Program T
Device = 16F18346
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINT32, WDTE = OFF, LVP = ON
Dim n, q, r, refq, refr As Word
Volatile Dim errors, checked As LongWord
n = 0
Do
    q = n / 10
    r = n Mod 10
    If q <> refq Or r <> refr Then
        errors = errors + 1
    End If
    checked = checked + 1
    refr = refr + 1
    If refr = 10 Then
        refr = 0
        refq = refq + 1
    End If
    If n = 65535 Then
        Break
    End If
    n = n + 1
Loop
