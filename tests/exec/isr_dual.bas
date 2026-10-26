' expect: ISRD_OK=1
' Two priorities (IPEN = 1): a low-priority handler (Timer0, free-running with a varying period)
' that a high-priority one (INT0, kicked from inside the low handler after a varying delay and
' re-arming itself) keeps interrupting while the main program computes. The low handler
' saves WREG/STATUS/BSR in software; the high one uses the hardware shadow registers. Both call
' the same routine inside Save, and neither may disturb the other's partial results or main's.
Program Isrd
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#if _has(PIR3.TMR0IF)
Dim T0If As PIR3.7
Dim T0Ie As PIE3.7
Dim T0Ip As IPR3.7
#else
Dim T0If As PIR0.5
Dim T0Ie As PIE0.5
Dim T0Ip As IPR0.5
#endif
#if _has(PIR3.TMR1IF)
Dim SwIf As PIR3.4
Dim SwIe As PIE3.4
Dim SwIp As IPR3.4
#else
Dim SwIf As PIR0.0
Dim SwIe As PIE0.0
Dim SwIp As IPR0.0
#endif
Dim hh As Word
Dim lh As Word
Dim hsum As LongWord
Dim lsum As LongWord
Dim ok As Byte
Dim inlow As Byte
Dim nest As Word
Dim t As LongWord
Dim r1 As LongWord
Dim r2 As LongWord
Dim arr(8) As Byte
Dim b0 As Word
Dim b1 As Word
Dim b2 As Word
Dim b3 As Word
Dim b4 As Word
Dim b5 As Word
Dim b6 As Word
Dim b7 As Word
Dim b8 As Word
Dim b9 As Word
Dim b10 As Word
Dim b11 As Word
Dim b12 As Word
Dim b13 As Word
Dim b14 As Word
Dim b15 As Word
Dim b16 As Word
Dim b17 As Word
Dim b18 As Word
Dim b19 As Word
Dim b20 As Word
Dim b21 As Word
Dim b22 As Word
Dim b23 As Word
Dim b24 As Word
Dim b25 As Word
Dim b26 As Word
Dim b27 As Word
Dim b28 As Word
Dim b29 As Word
Dim b30 As Word
Dim b31 As Word
Dim b32 As Word
Dim b33 As Word
Dim b34 As Word
Dim b35 As Word
Dim b36 As Word
Dim b37 As Word
Dim b38 As Word
Dim b39 As Word
Dim b40 As Word
Dim b41 As Word
Dim b42 As Word
Dim b43 As Word
Dim b44 As Word
Dim b45 As Word
Dim b46 As Word
Dim b47 As Word
Dim b48 As Word
Dim b49 As Word
Dim b50 As Word
Dim b51 As Word
Dim b52 As Word
Dim b53 As Word
Dim b54 As Word
Dim b55 As Word
Dim b56 As Word
Dim b57 As Word
Dim b58 As Word
Dim b59 As Word
Dim b60 As Word
Dim b61 As Word
Dim b62 As Word
Dim b63 As Word
Dim b64 As Word
Dim b65 As Word
Dim b66 As Word
Dim b67 As Word
Dim b68 As Word
Dim b69 As Word
' (the b<n> words overflow the Access Bank, so the main program also needs BSR to stay put)

Function Mix(ByVal x As Word) As Word
    Dim t As Word
    t = x * 3
    Result = t + 1
End Function

Function Work() As LongWord
    Dim i As Byte
    Dim acc As LongWord
    Dim w As Word
    acc = 0
    For i = 0 To 7
        arr(i) = i * 7
    Next
    For i = 0 To 7
        w = arr(i)
        acc = acc + w * 300 + Mix(w)
        acc = acc + arr(i) / 3
    Next
    b0 = acc
    b1 = b0 + 1
    b2 = b1 + 2
    b3 = b2 + 3
    b4 = b3 + 4
    b5 = b4 + 5
    b6 = b5 + 6
    b7 = b6 + 7
    b8 = b7 + 8
    b9 = b8 + 9
    b10 = b9 + 10
    b11 = b10 + 11
    b12 = b11 + 12
    b13 = b12 + 13
    b14 = b13 + 14
    b15 = b14 + 15
    b16 = b15 + 16
    b17 = b16 + 17
    b18 = b17 + 18
    b19 = b18 + 19
    b20 = b19 + 20
    b21 = b20 + 21
    b22 = b21 + 22
    b23 = b22 + 23
    b24 = b23 + 24
    b25 = b24 + 25
    b26 = b25 + 26
    b27 = b26 + 27
    b28 = b27 + 28
    b29 = b28 + 29
    b30 = b29 + 30
    b31 = b30 + 31
    b32 = b31 + 32
    b33 = b32 + 33
    b34 = b33 + 34
    b35 = b34 + 35
    b36 = b35 + 36
    b37 = b36 + 37
    b38 = b37 + 38
    b39 = b38 + 39
    b40 = b39 + 40
    b41 = b40 + 41
    b42 = b41 + 42
    b43 = b42 + 43
    b44 = b43 + 44
    b45 = b44 + 45
    b46 = b45 + 46
    b47 = b46 + 47
    b48 = b47 + 48
    b49 = b48 + 49
    b50 = b49 + 50
    b51 = b50 + 51
    b52 = b51 + 52
    b53 = b52 + 53
    b54 = b53 + 54
    b55 = b54 + 55
    b56 = b55 + 56
    b57 = b56 + 57
    b58 = b57 + 58
    b59 = b58 + 59
    b60 = b59 + 60
    b61 = b60 + 61
    b62 = b61 + 62
    b63 = b62 + 63
    b64 = b63 + 64
    b65 = b64 + 65
    b66 = b65 + 66
    b67 = b66 + 67
    b68 = b67 + 68
    b69 = b68 + 69
    acc = acc + b69
    Result = acc Xor (acc >> 3)
End Function

Interrupt Hi(ipHigh)
    Dim p As Word
    Dim q As Word
    SwIf = 0
    If inlow = 1 Then
        Inc(nest)
    End If
    Inc(hh)
    p = hh * 11
    hsum = hsum + p
    Save(0, Mix)
        q = Mix(p)
    Restore
    If hh < 150 Then
        SwIf = 1
    End If
End Interrupt

Interrupt Lo(ipLow)
    Dim p As Word
    Dim q As Word
    Dim k As Byte
    T0If = 0
    inlow = 1
    For k = 1 To (lh And 15)
        Inc(p)
    Next
    SwIf = 1
    Inc(lh)
    p = lh * 13
    lsum = lsum + p
    Save(0, Mix)
        q = Mix(p)
    Restore
    If lh < 150 Then
        TMR0H = 200 + (lh And 31)
    Else
        T0CON0 = 0
    End If
    inlow = 0
End Interrupt

T0Ip = 0
SwIp = 1
T0Ie = 1
SwIe = 1
Enable(Hi)
Enable(Lo)
r1 = Work()
T0CON1 = 65
T0CON0 = 128
r2 = Work()
While hh < 150 Or lh < 150
Wend
Disable(Lo)
Disable(Hi)
' Each handler's running sum must match its own count: sum(1..n) * factor.
ok = 1
If nest = 0 Then
    ok = 0
End If
If r1 <> r2 Then
    ok = 0
End If
t = hh
t = t * (t + 1) / 2 * 11
If hsum <> t Then
    ok = 0
End If
t = lh
t = t * (t + 1) / 2 * 13
If lsum <> t Then
    ok = 0
End If
