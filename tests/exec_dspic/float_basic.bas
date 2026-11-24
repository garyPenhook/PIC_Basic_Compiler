' expect: FB_G=3 FB_LT=1 FB_GE=0 FB_KEEP=4660 FB_Y=2143289344 FB_H=1073741823 FB_SQ=100 FB_NEG=1
' Float on the dsPIC33: arithmetic, comparisons and conversions (the XC-DSC soft-float routines behind lib/floatlib.bas).
' KEEP is the first variable, at the start of RAM, where the C library's own `errno` used to be linked: dividing by a NaN sets
' it, so the program defines `_errno` itself and KEEP must stay as it was. HW is the largest float divided by 2^127, which is
' a normal number although 2^-127 is not.
Program Fb
Device = dsPIC33CK64MC105
Clock = 8
Config FWDTEN = ON_SW

Dim keep As Word
Dim f As Float
Dim g As Integer
Dim lt As Byte
Dim ge As Byte
Dim x As Float
Dim xw As x.AsLongWord
Dim y As Float
Dim yw As y.AsLongWord
Dim h As Float
Dim hw As h.AsLongWord
Dim sq As Integer
Dim neg As Byte
Dim n As Float

keep = 4660
f = 1.5
n = f * 2.0 + 0.25
g = Integer(n)
lt = 0
If f < 2.5 Then
    lt = 1
End If
ge = 0
If f >= 2.5 Then
    ge = 1
End If
xw = $7F800001
y = 2.0 / x
xw = $7F7FFFFF
h = x / 170141183460469231731687303715884105728.0
f = 10.0
f = f * f
sq = Integer(f)
n = -f
neg = 0
If n < 0.0 Then
    neg = 1
End If
Terminate
