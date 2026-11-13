' expect: PR_BAD=0 PR_N=508
' Pinio against a plain-Basic reference (the straight comparison chains the module used before its FSR0 routines), for every pin
' number 0..31 and a few beyond, both levels, two start patterns. The reference reads and writes the same registers, so bits a part
' does not implement (RA3 as an input, the upper bits of LATA on the small parts) behave the same in both and cancel out.
' PinGet reads PORTx: with the pins digital outputs and a different pattern on each port, MDB reads back LATx on the implemented
' bits, so a wrong port, bit or mask shows (a different pattern per pass, so the 1s and 0s are both read).
Program Pr
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "pinio"
Dim bad As Word
Dim n As Word
Dim i As Byte
Dim t As Byte
Dim pat As Byte
Dim lv As Boolean
Dim la1 As Byte
Dim lb1 As Byte
Dim lc1 As Byte
Dim ta1 As Byte
Dim tb1 As Byte
Dim tc1 As Byte
Dim na1 As Byte
Dim nb1 As Byte
Dim nc1 As Byte
Dim la2 As Byte
Dim lb2 As Byte
Dim lc2 As Byte
Dim ta2 As Byte
Dim tb2 As Byte
Dim tc2 As Byte
Dim na2 As Byte
Dim nb2 As Byte
Dim nc2 As Byte
Dim ones As Word
Dim g1 As Boolean
Dim g2 As Boolean

Sub Preset()
    LATA = pat
    TRISA = pat
    ANSELA = pat
#if _has(LATB)
    LATB = pat Xor 255
    TRISB = pat Xor 255
    ANSELB = pat Xor 255
#endif
#if _has(LATC)
    LATC = pat
    TRISC = pat Xor 15
    ANSELC = pat Xor 240
#endif
End Sub

Sub PrepGet()
    TRISA = 0
    ANSELA = 0
    LATA = pat
#if _has(LATB)
    TRISB = 0
    ANSELB = 0
    LATB = pat Xor 255
#endif
#if _has(LATC)
    TRISC = 0
    ANSELC = 0
    LATC = pat Xor 60
#endif
End Sub

Sub Snap1()
    la1 = LATA
    ta1 = TRISA
    na1 = ANSELA
#if _has(LATB)
    lb1 = LATB
    tb1 = TRISB
    nb1 = ANSELB
#endif
#if _has(LATC)
    lc1 = LATC
    tc1 = TRISC
    nc1 = ANSELC
#endif
End Sub

Sub Snap2()
    la2 = LATA
    ta2 = TRISA
    na2 = ANSELA
#if _has(LATB)
    lb2 = LATB
    tb2 = TRISB
    nb2 = ANSELB
#endif
#if _has(LATC)
    lc2 = LATC
    tc2 = TRISC
    nc2 = ANSELC
#endif
End Sub

Sub Check()
    n = n + 1
    If la1 <> la2 Or ta1 <> ta2 Or na1 <> na2 Then
        bad = bad + 1
    End If
    If lb1 <> lb2 Or tb1 <> tb2 Or nb1 <> nb2 Or lc1 <> lc2 Or tc1 <> tc2 Or nc1 <> nc2 Then
        bad = bad + 1
    End If
End Sub

Sub RefSet(ByVal pin As Byte, ByVal level As Boolean)
    Dim m As Byte
    m = 1 << (pin And 7)
    If pin < 8 Then
        If level Then
            LATA = LATA Or m
        Else
            LATA = LATA And (m Xor 255)
        End If
#if _has(LATB)
    ElseIf pin < 16 Then
        If level Then
            LATB = LATB Or m
        Else
            LATB = LATB And (m Xor 255)
        End If
#endif
#if _has(LATC)
    ElseIf pin >= 16 And pin < 24 Then
        If level Then
            LATC = LATC Or m
        Else
            LATC = LATC And (m Xor 255)
        End If
#endif
    End If
End Sub

Sub RefOutput(ByVal pin As Byte)
    Dim m As Byte
    Dim k As Byte
    m = 1 << (pin And 7)
    k = m Xor 255
    If pin < 8 Then
        ANSELA = ANSELA And k
        TRISA = TRISA And k
#if _has(LATB)
    ElseIf pin < 16 Then
        ANSELB = ANSELB And k
        TRISB = TRISB And k
#endif
#if _has(LATC)
    ElseIf pin >= 16 And pin < 24 Then
        ANSELC = ANSELC And k
        TRISC = TRISC And k
#endif
    End If
End Sub

Sub RefInput(ByVal pin As Byte)
    Dim m As Byte
    m = 1 << (pin And 7)
    If pin < 8 Then
        ANSELA = ANSELA And (m Xor 255)
        TRISA = TRISA Or m
#if _has(LATB)
    ElseIf pin < 16 Then
        ANSELB = ANSELB And (m Xor 255)
        TRISB = TRISB Or m
#endif
#if _has(LATC)
    ElseIf pin >= 16 And pin < 24 Then
        ANSELC = ANSELC And (m Xor 255)
        TRISC = TRISC Or m
#endif
    End If
End Sub

Function RefGet(ByVal pin As Byte) As Boolean
    Dim m As Byte
    m = 1 << (pin And 7)
    Result = False
    If pin < 8 Then
        Result = (PORTA And m) <> 0
#if _has(LATB)
    ElseIf pin < 16 Then
        Result = (PORTB And m) <> 0
#endif
#if _has(LATC)
    ElseIf pin >= 16 And pin < 24 Then
        Result = (PORTC And m) <> 0
#endif
    End If
End Function

' One pass over the pins and levels for the start pattern in `pat`.
Sub Pass()
    For i = 0 To 35
        For t = 0 To 1
            lv = t = 1
            Preset()
            Pinio.PinSet(i, lv)
            Snap1()
            Preset()
            RefSet(i, lv)
            Snap2()
            Check()
        Next
        Preset()
        Pinio.PinOutput(i)
        Snap1()
        Preset()
        RefOutput(i)
        Snap2()
        Check()
        Preset()
        Pinio.PinInput(i)
        Snap1()
        Preset()
        RefInput(i)
        Snap2()
        Check()
        Preset()
        Pinio.PinDriveLow(i)
        Snap1()
        Preset()
        RefSet(i, False)
        RefOutput(i)
        Snap2()
        Check()
        Preset()
        Pinio.PinRelease(i)
        Snap1()
        Preset()
        RefInput(i)
        Snap2()
        Check()
        PrepGet()
        g1 = Pinio.PinGet(i)
        g2 = RefGet(i)
        n = n + 1
        If g1 <> g2 Then
            bad = bad + 1
        End If
        If g1 Then
            ones = ones + 1
        End If
    Next
End Sub

bad = 0
n = 0
ones = 0
pat = 165
Pass()
pat = 90
Pass()
For i = 100 To 255 Step 51
    Preset()
    Pinio.PinSet(i, True)
    Snap1()
    Preset()
    Snap2()
    Check()
Next
