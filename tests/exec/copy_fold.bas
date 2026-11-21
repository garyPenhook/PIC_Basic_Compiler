' expect: CF_CF_P19=1 CF_CF_P3=0 CF_CF_P22=0 CF_CF_P13=1 CF_CF_PRUN=1 CF_CF_T10=55 CF_CF_TRUN=6 CF_CF_C1=65 CF_CF_C2=63 CF_CF_C3=63 CF_CF_G1=7 CF_CF_G2=9 CF_CF_L1=1 CF_CF_L2=0 CF_CF_L3=1 CF_CF_BIG=0
' Calls with constant arguments of routines that only compute are run by the compiler (PinOk, with an Exit, and Tri, with a
' loop); the same routines called at run time must give the same values. A local copied from a parameter at the top of a
' routine lives in the parameter (PutCh). A Boolean stored and tested at once keeps its store and branches on Z (LoadIt),
' and a non-zero test made a Boolean loses its movlw 0 (Level). The 600-byte array makes the start-up clear one loop
' that runs FSR0 to an end address.
Program Cf
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim big(600) As Byte
Dim cf_k As Byte
Volatile Dim cf_p19 As Byte
Volatile Dim cf_p3 As Byte
Volatile Dim cf_p22 As Byte
Volatile Dim cf_p13 As Byte
Volatile Dim cf_prun As Byte
Volatile Dim cf_t10 As Word
Volatile Dim cf_trun As Word
Dim cf_c As Byte
Volatile Dim cf_c1 As Byte
Volatile Dim cf_c2 As Byte
Volatile Dim cf_c3 As Byte
Volatile Dim cf_g1 As Byte
Volatile Dim cf_g2 As Byte
Volatile Dim cf_l1 As Byte
Volatile Dim cf_l2 As Byte
Volatile Dim cf_l3 As Byte
Volatile Dim cf_big As Byte

Function PinOk(ByVal pin As Byte) As Boolean
    Result = (pin <= 5 And pin <> 3) Or (pin >= 16 And pin <= 21)
    If pin = 22 Then
        Exit
    End If
    If pin >= 12 And pin <= 15 Then
        Result = True
    End If
End Function

Function Tri(ByVal n As Byte) As Word
    Dim s As Word
    s = 0
    While n > 0
        s = s + n
        Dec(n)
    Wend
    Result = s
End Function

Sub PutCh(ByVal ch As Char)
    Dim code As Byte
    code = Byte(ch)
    If code < 32 Or code > 126 Then
        code = 63
    End If
    cf_c = code
End Sub

Function Level(ByVal v As Byte, ByVal m As Byte) As Boolean
    Result = (v And m) <> 0
End Function

Function LoadIt(ByVal x As Byte) As Byte
    Dim good As Boolean
    Dim i As Byte
    good = (x = 42)
    If good Then
        For i = 0 To 3
            If x + i > 45 Then
                good = False
            End If
        Next
    End If
    If Not good Then
        Result = 9
    Else
        Result = 7
    End If
End Function

cf_k = 3
' Inc then Dec: the value is unchanged, but the compiler no longer knows it, so the calls below run on the device
Inc(cf_k)
Dec(cf_k)
cf_p19 = Bit(PinOk(19))
cf_p3 = Bit(PinOk(3))
cf_p22 = Bit(PinOk(22))
cf_p13 = Bit(PinOk(13))
cf_prun = Bit(PinOk(cf_k + 16))
cf_t10 = Tri(10)
cf_trun = Tri(cf_k)
PutCh(Char(65))
cf_c1 = cf_c
PutCh(Char(cf_k))
cf_c2 = cf_c
PutCh(Char(cf_k + 124))
cf_c3 = cf_c
cf_g1 = LoadIt(cf_k + 39)
cf_g2 = LoadIt(cf_k + 40)
cf_l1 = Bit(Level(cf_k, 2))
cf_l2 = Bit(Level(cf_k, 4))
cf_l3 = Bit(Level(cf_k + 125, 128))
cf_big = big(0) Or big(599)
