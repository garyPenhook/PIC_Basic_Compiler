' Constant power-of-two division compared with the general runtime-divisor path.
' All ShortInt bit patterns, signed width limits, exact and inexact negative quotients.
' expect: DP_FAILURES=0 DP_CHECKS=2049 DP_CALLS=1 DP_NESTED=-1
Program DP
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Const LV(32) As LongInt = (-2147483648, -2147483647, -16777217, -16777216, -65537, -65536, -32769, -32768, -32767, -257, -256, -255, -129, -128, -127, -33, -32, -31, -9, -8, -7, -1, 0, 1, 7, 8, 9, 255, 256, 65535, 2147483646, 2147483647)
Const IV(32) As Integer = (-32768, -32767, -16385, -16384, -8193, -8192, -4097, -4096, -1025, -1024, -513, -512, -257, -256, -255, -129, -128, -127, -33, -32, -31, -9, -8, -7, -1, 0, 1, 7, 8, 9, 32766, 32767)
#option Optimize = Speed
Dim i As Byte
Dim sv, sq As ShortInt
Dim ivalue, iq As Integer
Dim lvalue, lq As LongInt
Volatile Dim sd As ShortInt
Volatile Dim id As Integer
Volatile Dim ld As LongInt
Volatile Dim failures, checks, calls As Word
Volatile Dim nested As LongInt
Volatile Dim callvalue As LongInt

NoInline Function NextValue() As LongInt
    calls = calls + 1
    Result = callvalue
End Function

For i = 0 To 255
    sv = ShortInt(i)
    sd = 2
    sq = sv / 2
    If sq <> sv / sd Then
        failures = failures + 1
    End If
    checks = checks + 1
    sd = 4
    sq = sv / 4
    If sq <> sv / sd Then
        failures = failures + 1
    End If
    checks = checks + 1
    sd = 8
    sq = sv / 8
    If sq <> sv / sd Then
        failures = failures + 1
    End If
    checks = checks + 1
    sd = 16
    sq = sv / 16
    If sq <> sv / sd Then
        failures = failures + 1
    End If
    checks = checks + 1
    sd = 32
    sq = sv / 32
    If sq <> sv / sd Then
        failures = failures + 1
    End If
    checks = checks + 1
    sd = 64
    sq = sv / 64
    If sq <> sv / sd Then
        failures = failures + 1
    End If
    checks = checks + 1
Next

For i = 0 To 31
    ivalue = IV(i)
    lvalue = LV(i)
    id = 2
    iq = ivalue / 2
    If iq <> ivalue / id Then
        failures = failures + 1
    End If
    checks = checks + 1
    ld = 2
    lq = lvalue / 2
    If lq <> lvalue / ld Then
        failures = failures + 1
    End If
    checks = checks + 1
    id = 4
    iq = ivalue / 4
    If iq <> ivalue / id Then
        failures = failures + 1
    End If
    checks = checks + 1
    ld = 4
    lq = lvalue / 4
    If lq <> lvalue / ld Then
        failures = failures + 1
    End If
    checks = checks + 1
    id = 8
    iq = ivalue / 8
    If iq <> ivalue / id Then
        failures = failures + 1
    End If
    checks = checks + 1
    ld = 8
    lq = lvalue / 8
    If lq <> lvalue / ld Then
        failures = failures + 1
    End If
    checks = checks + 1
    id = 16
    iq = ivalue / 16
    If iq <> ivalue / id Then
        failures = failures + 1
    End If
    checks = checks + 1
    ld = 16
    lq = lvalue / 16
    If lq <> lvalue / ld Then
        failures = failures + 1
    End If
    checks = checks + 1
    id = 32
    iq = ivalue / 32
    If iq <> ivalue / id Then
        failures = failures + 1
    End If
    checks = checks + 1
    ld = 32
    lq = lvalue / 32
    If lq <> lvalue / ld Then
        failures = failures + 1
    End If
    checks = checks + 1
    id = 64
    iq = ivalue / 64
    If iq <> ivalue / id Then
        failures = failures + 1
    End If
    checks = checks + 1
    ld = 64
    lq = lvalue / 64
    If lq <> lvalue / ld Then
        failures = failures + 1
    End If
    checks = checks + 1
    id = 128
    iq = ivalue / 128
    If iq <> ivalue / id Then
        failures = failures + 1
    End If
    checks = checks + 1
    ld = 128
    lq = lvalue / 128
    If lq <> lvalue / ld Then
        failures = failures + 1
    End If
    checks = checks + 1
    id = 256
    iq = ivalue / 256
    If iq <> ivalue / id Then
        failures = failures + 1
    End If
    checks = checks + 1
    ld = 256
    lq = lvalue / 256
    If lq <> lvalue / ld Then
        failures = failures + 1
    End If
    checks = checks + 1
Next
callvalue = -10
nested = (NextValue() + 1) / 8
If nested <> -1 Then
    failures = failures + 1
End If
checks = checks + 1
