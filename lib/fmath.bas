Module FMath
' Run-time maths for the Float type: square root, exponential, logarithms and the trigonometric
' functions, built on Float's + - * / and FScale (see FloatLib). Names start with F so that they
' do not clash with the build-time Sqr, Sin, Cos, Pow and Log2.
'
' Accuracy is a few units in the sixth digit. FSin, FCos and FTan reduce the angle by whole turns in
' Integer arithmetic, so |x| must stay under 200000 radians (a larger angle gives NaN) and they are
' best used under 1000. A result too big for a Float is infinity, one too small is zero.
' FSqr, FLog and FLog10 of a negative number, and FLog of zero, give NaN and -infinity.
Include "floatlib"

Const PosInf As LongWord = $7F800000
Const NegInf As LongWord = $FF800000
Const NaN As LongWord = $7FC00000

' Square root: Newton steps from a guess made by halving the exponent.
Public Function FSqr(ByVal x As Float) As Float
    Dim xw As x.AsLongWord
    Dim g As Float
    Dim gw As g.AsLongWord
    Dim i As Byte
    If xw = 0 Or xw = $80000000 Then
        gw = 0
    ElseIf (xw And $80000000) <> 0 Or (xw And $7F800000) = $7F800000 Then
        gw = NaN
        If xw = PosInf Then
            gw = PosInf
        End If
    Else
        gw = (xw >> 1) + $1FBD1DF5
        For i = 1 To 4
            g = 0.5 * (g + x / g)
        Next
    End If
    Result = g
End Function

' Natural logarithm: x = m * 2^e with m in [0.71, 1.42), ln m from the series of atanh.
Public Function FLog(ByVal x As Float) As Float
    Dim xw As x.AsLongWord
    Dim m As Float
    Dim mw As m.AsLongWord
    Dim s, s2, t As Float
    Dim r As Float
    Dim rw As r.AsLongWord
    Dim e As Integer
    If xw = 0 Or xw = $80000000 Then
        rw = NegInf
    ElseIf (xw And $80000000) <> 0 Or (xw And $7F800000) = $7F800000 Then
        rw = NaN
        If xw = PosInf Then
            rw = PosInf
        End If
    Else
        e = Integer((xw >> 23) And 255) - 127
        mw = (xw And $007FFFFF) Or $3F800000
        If m > 1.41421356 Then
            m = m * 0.5
            Inc(e)
        End If
        s = (m - 1) / (m + 1)
        s2 = s * s
        t = s2 * (1.0 / 9)
        t = (t + 1.0 / 7) * s2
        t = (t + 0.2) * s2
        t = (t + 1.0 / 3) * s2
        t = (t + 1) * s
        r = 2 * t + Float(e) * 0.693147181
    End If
    Result = r
End Function

Public Function FLog10(ByVal x As Float) As Float
    Result = FLog(x) * 0.434294482
End Function

' e to the power x: x = n ln 2 + r, e^r from its Taylor series, then scaled by 2^n.
Public Function FExp(ByVal x As Float) As Float
    Dim xw As x.AsLongWord
    Dim r, t As Float
    Dim rw As r.AsLongWord
    Dim n As Integer
    If (xw And $7F800000) = $7F800000 And (xw And $007FFFFF) <> 0 Then
        rw = NaN
    ElseIf x > 88.7228 Then
        rw = PosInf
    ElseIf x < -87.3365 Then
        rw = 0
    Else
        t = x * 1.44269504
        If t >= 0 Then
            n = Integer(t + 0.5)
        Else
            n = Integer(t - 0.5)
        End If
        r = x - Float(n) * 0.693359375
        r = r + Float(n) * 0.000212194440
        t = r * (1.0 / 5040)
        t = (t + 1.0 / 720) * r
        t = (t + 1.0 / 120) * r
        t = (t + 1.0 / 24) * r
        t = (t + 1.0 / 6) * r
        t = (t + 0.5) * r
        t = (t + 1) * r + 1
        r = t
        rw = FScale(rw, ShortInt(n))
    End If
    Result = r
End Function

' x to the power y for x > 0.
Public Function FPow(ByVal x As Float, ByVal y As Float) As Float
    Result = FExp(y * FLog(x))
End Function

' Sine, x in radians.
Public Function FSin(ByVal x As Float) As Float
    Dim r, t, q As Float
    Dim rw As r.AsLongWord
    Dim k As Integer
    If x > 200000 Or x < -200000 Then
        rw = NaN
    Else
        q = x * 0.159154943
        If q >= 0 Then
            k = Integer(q + 0.5)
        Else
            k = Integer(q - 0.5)
        End If
        r = x - Float(k) * 6.28125
        r = r - Float(k) * 0.00193530718
        If r > 1.57079633 Then
            r = 3.14159265 - r
        ElseIf r < -1.57079633 Then
            r = -3.14159265 - r
        End If
        q = r * r
        t = q * (-1.0 / 39916800)
        t = (t + 1.0 / 362880) * q
        t = (t - 1.0 / 5040) * q
        t = (t + 1.0 / 120) * q
        t = (t - 1.0 / 6) * q
        r = r + r * t
    End If
    Result = r
End Function

Public Function FCos(ByVal x As Float) As Float
    Result = FSin(x + 1.57079633)
End Function

Public Function FTan(ByVal x As Float) As Float
    Result = FSin(x) / FCos(x)
End Function
