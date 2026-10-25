Module FloatLib
' Single-precision (IEEE-754 binary32) arithmetic for the Float type.
'
' The compiler includes this module by itself when a program mentions Float, and turns every Float
' operation into a call to one of the routines below; nothing here needs to be called by hand.
' A Float is held as its 32-bit pattern in a LongWord: sign (bit 31), biased exponent (bits 30..23),
' 23 fraction bits. Only the routines a program uses are linked.
'
' Behaviour: round to nearest, ties to even. Infinities and NaN are produced and propagated
' (every NaN is $7FC00000). Denormals are not supported: an exponent field of 0 is read as zero and
' a result too small for a normal number becomes a signed zero.
'
' The mantissa work uses a 27-bit form: the leading one at bit 26, 23 fraction bits below it, then
' guard (bit 2), round (bit 1) and sticky (bit 0). Pack rounds that form and assembles the result.

Const NaNBits As LongWord = $7FC00000
Const SignBit As LongWord = $80000000

' Rounds the 27-bit mantissa `m` (leading one at bit 26) and builds the result with exponent `e`.
Private Function Pack(ByVal sign As LongWord, ByVal e As Integer, ByVal m As LongWord) As LongWord
    Dim rb As LongWord
    rb = m And 7
    m = m >> 3
    If rb > 4 Then
        Inc(m)
    ElseIf rb = 4 Then
        If (m And 1) = 1 Then
            Inc(m)
        End If
    End If
    If m >= $1000000 Then
        m = m >> 1
        Inc(e)
    End If
    If e >= 255 Then
        Result = sign Or $7F800000
    ElseIf e <= 0 Then
        Result = sign
    Else
        Result = sign Or (LongWord(e) << 23) Or (m And $7FFFFF)
    End If
End Function

Public Function FAdd(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Dim ea, eb, d As Integer
    Dim sh As Byte
    Dim ma, mb, t, lost As LongWord
    Dim sa, sb As LongWord
    ea = Integer((a >> 23) And $FF)
    eb = Integer((b >> 23) And $FF)
    sa = a And SignBit
    sb = b And SignBit
    If ea = 255 Or eb = 255 Then
        If ea = 255 And (a And $7FFFFF) <> 0 Then
            Result = NaNBits
        ElseIf eb = 255 And (b And $7FFFFF) <> 0 Then
            Result = NaNBits
        ElseIf ea = 255 And eb = 255 And sa <> sb Then
            Result = NaNBits
        ElseIf ea = 255 Then
            Result = a
        Else
            Result = b
        End If
        Exit
    End If
    If ea = 0 Then
        If eb = 0 Then
            Result = sa And sb
        Else
            Result = b
        End If
        Exit
    End If
    If eb = 0 Then
        Result = a
        Exit
    End If
    ' Make a the operand with the larger magnitude.
    If (b And $7FFFFFFF) > (a And $7FFFFFFF) Then
        t = a
        a = b
        b = t
        t = sa
        sa = sb
        sb = t
        d = ea
        ea = eb
        eb = d
    End If
    ma = ((a And $7FFFFF) Or $800000) << 3
    mb = ((b And $7FFFFF) Or $800000) << 3
    d = ea - eb
    If d > 0 Then
        If d > 26 Then
            mb = 1
        Else
            sh = Byte(d)
            lost = mb And ((LongWord(1) << sh) - 1)
            mb = mb >> sh
            If lost <> 0 Then
                mb = mb Or 1
            End If
        End If
    End If
    If sa = sb Then
        ma = ma + mb
        If ma >= $8000000 Then
            ma = (ma >> 1) Or (ma And 1)
            Inc(ea)
        End If
    Else
        ma = ma - mb
        If ma = 0 Then
            Result = 0
            Exit
        End If
        While ma < $4000000
            ma = ma << 1
            Dec(ea)
        Wend
    End If
    Result = Pack(sa, ea, ma)
End Function

Public Function FSub(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Result = FAdd(a, b Xor SignBit)
End Function

Public Function FMul(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Dim ea, eb, e As Integer
    Dim ma, mb, ah, al, bh, bl, hi, mid, lo, h, l, m As LongWord
    Dim sign As LongWord
    ea = Integer((a >> 23) And $FF)
    eb = Integer((b >> 23) And $FF)
    sign = (a Xor b) And SignBit
    If ea = 255 Or eb = 255 Then
        If ea = 255 And (a And $7FFFFF) <> 0 Then
            Result = NaNBits
        ElseIf eb = 255 And (b And $7FFFFF) <> 0 Then
            Result = NaNBits
        ElseIf ea = 0 Or eb = 0 Then
            Result = NaNBits
        Else
            Result = sign Or $7F800000
        End If
        Exit
    End If
    If ea = 0 Or eb = 0 Then
        Result = sign
        Exit
    End If
    ma = (a And $7FFFFF) Or $800000
    mb = (b And $7FFFFF) Or $800000
    ' 24 x 24 bit product in 12-bit halves: hi * 2^24 + mid * 2^12 + lo.
    ah = ma >> 12
    al = ma And $FFF
    bh = mb >> 12
    bl = mb And $FFF
    hi = ah * bh
    mid = ah * bl + al * bh
    lo = al * bl + ((mid And $FFF) << 12)
    h = hi + (mid >> 12) + (lo >> 24)
    l = lo And $FFFFFF
    e = ea + eb - 127
    If h >= $800000 Then
        Inc(e)
        m = (h << 3) Or (l >> 21)
        If (l And $1FFFFF) <> 0 Then
            m = m Or 1
        End If
    Else
        m = (h << 4) Or (l >> 20)
        If (l And $FFFFF) <> 0 Then
            m = m Or 1
        End If
    End If
    Result = Pack(sign, e, m)
End Function

Public Function FDiv(ByVal a As LongWord, ByVal b As LongWord) As LongWord
    Dim ea, eb, e As Integer
    Dim ma, mb, q As LongWord
    Dim sign As LongWord
    Dim i As Byte
    ea = Integer((a >> 23) And $FF)
    eb = Integer((b >> 23) And $FF)
    sign = (a Xor b) And SignBit
    If ea = 255 Or eb = 255 Then
        If ea = 255 And (a And $7FFFFF) <> 0 Then
            Result = NaNBits
        ElseIf eb = 255 And (b And $7FFFFF) <> 0 Then
            Result = NaNBits
        ElseIf ea = 255 And eb = 255 Then
            Result = NaNBits
        ElseIf ea = 255 Then
            Result = sign Or $7F800000
        Else
            Result = sign
        End If
        Exit
    End If
    If eb = 0 Then
        If ea = 0 Then
            Result = NaNBits
        Else
            Result = sign Or $7F800000
        End If
        Exit
    End If
    If ea = 0 Then
        Result = sign
        Exit
    End If
    ma = (a And $7FFFFF) Or $800000
    mb = (b And $7FFFFF) Or $800000
    e = ea - eb + 127
    If ma < mb Then
        ma = ma << 1
        Dec(e)
    End If
    ' 27 quotient bits, the first is the integer bit: ma / mb is in [1, 2).
    q = 0
    For i = 1 To 27
        q = q << 1
        If ma >= mb Then
            ma = ma - mb
            q = q Or 1
        End If
        ma = ma << 1
    Next
    ' ma is now twice the remainder: non-zero means inexact (sticky).
    If ma <> 0 Then
        q = q Or 1
    End If
    Result = Pack(sign, e, q)
End Function

' -1, 0 or 1 for a < b, a = b, a > b (+0 equals -0); 2 when either is NaN.
Private Function Cmp(ByVal a As LongWord, ByVal b As LongWord) As ShortInt
    Dim ma, mb As LongWord
    ma = a And $7FFFFFFF
    mb = b And $7FFFFFFF
    If ma > $7F800000 Or mb > $7F800000 Then
        Result = 2
    ElseIf ma = 0 And mb = 0 Then
        Result = 0
    ElseIf (a And SignBit) <> (b And SignBit) Then
        If (a And SignBit) <> 0 Then
            Result = -1
        Else
            Result = 1
        End If
    ElseIf ma = mb Then
        Result = 0
    ElseIf (ma < mb) = ((a And SignBit) = 0) Then
        Result = -1
    Else
        Result = 1
    End If
End Function

Public Function FEq(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Result = Cmp(a, b) = 0
End Function

Public Function FNe(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Result = Cmp(a, b) <> 0
End Function

Public Function FLt(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Result = Cmp(a, b) = -1
End Function

Public Function FLe(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Dim c As ShortInt
    c = Cmp(a, b)
    Result = c = -1 Or c = 0
End Function

Public Function FGt(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Result = Cmp(a, b) = 1
End Function

Public Function FGe(ByVal a As LongWord, ByVal b As LongWord) As Boolean
    Dim c As ShortInt
    c = Cmp(a, b)
    Result = c = 1 Or c = 0
End Function

' The Float for an unsigned magnitude `m` and sign bit `sign`.
Private Function FromMag(ByVal sign As LongWord, ByVal m As LongWord) As LongWord
    Dim e As Integer
    Dim s As LongWord
    If m = 0 Then
        Result = 0
        Exit
    End If
    e = 158
    While m < $80000000
        m = m << 1
        Dec(e)
    Wend
    s = m And $1F
    m = m >> 5
    If s <> 0 Then
        m = m Or 1
    End If
    Result = Pack(sign, e, m)
End Function

Public Function FFromLong(ByVal v As LongInt) As LongWord
    If v < 0 Then
        Result = FromMag(SignBit, LongWord(0 - v))
    Else
        Result = FromMag(0, LongWord(v))
    End If
End Function

Public Function FFromULong(ByVal v As LongWord) As LongWord
    Result = FromMag(0, v)
End Function

' Truncates toward zero; out of range saturates to the LongInt limits, NaN gives 0.
Public Function FToLong(ByVal a As LongWord) As LongInt
    Dim e As Integer
    Dim sh As Byte
    Dim m As LongWord
    Dim neg As Boolean
    e = Integer((a >> 23) And $FF)
    neg = (a And SignBit) <> 0
    If e < 127 Or (e = 255 And (a And $7FFFFF) <> 0) Then
        Result = 0
    ElseIf e >= 158 Then
        If neg Then
            Result = -2147483647 - 1
        Else
            Result = 2147483647
        End If
    Else
        m = (a And $7FFFFF) Or $800000
        If e >= 150 Then
            sh = Byte(e - 150)
            m = m << sh
        Else
            sh = Byte(150 - e)
            m = m >> sh
        End If
        If neg Then
            Result = 0 - LongInt(m)
        Else
            Result = LongInt(m)
        End If
    End If
End Function
