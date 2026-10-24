' expect: T_A=10 T_AV=10 T_B=255 T_BV=255 T_C=6 T_CV=1 T_D=100 T_DV=1 T_E=21 T_EV=1 T_F=36 T_FV=1 T_G=5 T_GV=5 T_H=45 T_HV=9 T_II=8 T_M=10 T_K=6 T_KV=6 T_L=300 T_LV=300 T_N=36 T_NV=40 T_P=55 T_PV=1 T_Q=5 T_QV=5 T_R=21 T_RV=7 T_SS=15 T_SSV=1 T_U=15
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim i As Byte
Dim wi As Word
Dim si As ShortInt
Dim a, av, b, bv, c, cv, d, dv, e, ev, f, fv, g, gv, h, hv As Byte
Dim ii, j, k, kv, m As Byte
Dim l, lv As Word
Dim seen As Byte
Dim n, nv, p, pv, q, qv, r, rv, ss, ssv, u As Byte
Dim pw As Word
Dim cur As Byte

Sub Seecur()
    u = u + cur
End Sub

Sub Bump()
    seen = seen + 1
End Sub

' 10 passes, variable not used in the body, leaves the last value it took
For i = 1 To 10
    a = a + 1
Next
av = i
' 255 passes, the longest counted loop
For i = 1 To 255
    b = b + 1
Next
bv = i
' count down by 1, six passes
For i = 6 To 1 Step -1
    c = c + 1
Next
cv = i
' Word variable, 100 passes
For wi = 1000 To 1099
    d = d + 1
Next
If wi = 1099 Then
    dv = 1
End If
' step 3 from 0 to 20: 0,3,...,18 is 7 passes, last value 18
For i = 0 To 20 Step 3
    e = e + 3
Next
If i = 18 Then
    ev = 1
End If
' signed variable counting down by 2 from 10 to -60: 36 passes
For si = 10 To -60 Step -2
    f = f + 1
Next
If si = -60 Then
    fv = 1
End If
' Continue skips the rest of the body but still counts
For i = 1 To 5
    g = g + 1
    Continue
    g = g + 100
Next
gv = i
' nested counted loops, 9 x 5
For i = 1 To 9
    For j = 1 To 5
        h = h + 1
    Next
Next
hv = i
' a call in the body with a global loop variable: not counted, still correct
For i = 1 To 8
    Bump()
Next
ii = seen
' the body reads the variable: not counted, still correct
For i = 1 To 4
    m = m + i
Next
' Break inside: not counted, still correct
For i = 1 To 20
    k = k + 1
    If k = 6 Then
        Break
    End If
Next
kv = i
' a single pass
For i = 4 To 4
    l = l + 300
Next
lv = l

' the body reads the variable and the loop is still counted: sum 1..8 = 36, variable ends at 8
For i = 1 To 8
    n = n + i
Next
If i = 8 Then
    nv = 40
End If
' Word variable read in the body: 1..10 sum = 55
For wi = 1 To 10
    p = p + wi
Next
If wi = 10 Then
    pv = 1
End If
' Break keeps the current value
For i = 1 To 200
    q = i
    If i = 5 Then
        Break
    End If
Next
qv = i
' descending, read in the body, with a stride: 1 + 4 + ... + 19? 19,16,...,1 = 7 values, sum 70 -> r counts passes
For i = 19 To 1 Step -3
    r = r + 3
Next
If i = 1 Then
    rv = 7
End If
' a global the callee reads: Seecur sees the current value each pass (1..5 -> 15)
For cur = 1 To 5
    Seecur()
Next
ss = u
If cur = 5 Then
    ssv = 1
End If
