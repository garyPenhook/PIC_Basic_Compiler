' expect: LSP_BAD=0 LSP_BADOFF=0 LSP_N=32
' Module review 23 (spi), PIC18F27Q10 at 64 MHz: every pin the host takes (RB0..RC7) as SCK, then as SDO, is routed alone through RxyPPS (codes 15 and 16) and given back by SpiOff; the pin numbers are run-time values, so the comparison chain in SetPps runs in full.
Program Lsp
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "spi"
Dim pin As Byte
Dim sck As Byte
Dim sdi As Byte
Dim ok As Byte
Dim v As Byte
Dim s As Byte
Dim bad As Byte
Dim badoff As Byte
Dim n As Byte
bad = 0
badoff = 0
n = 0
For pin = 8 To 23
    sdi = 8
    If pin = 8 Then
        sdi = 9
    End If
    ok = Spi.SpiInit(1000000, 0, pin, 255, sdi)
    Inc(n)
    v = 0
    If pin = 8 Then
        v = RB0PPS
    ElseIf pin = 9 Then
        v = RB1PPS
    ElseIf pin = 10 Then
        v = RB2PPS
    ElseIf pin = 11 Then
        v = RB3PPS
    ElseIf pin = 12 Then
        v = RB4PPS
    ElseIf pin = 13 Then
        v = RB5PPS
    ElseIf pin = 14 Then
        v = RB6PPS
    ElseIf pin = 15 Then
        v = RB7PPS
    ElseIf pin = 16 Then
        v = RC0PPS
    ElseIf pin = 17 Then
        v = RC1PPS
    ElseIf pin = 18 Then
        v = RC2PPS
    ElseIf pin = 19 Then
        v = RC3PPS
    ElseIf pin = 20 Then
        v = RC4PPS
    ElseIf pin = 21 Then
        v = RC5PPS
    ElseIf pin = 22 Then
        v = RC6PPS
    ElseIf pin = 23 Then
        v = RC7PPS
    End If
    s = RB0PPS + RB1PPS + RB2PPS + RB3PPS + RB4PPS + RB5PPS + RB6PPS + RB7PPS + RC0PPS + RC1PPS + RC2PPS + RC3PPS + RC4PPS + RC5PPS + RC6PPS + RC7PPS
    If ok <> 1 Or v <> 15 Or s <> 15 Then
        Inc(bad)
    End If
    Spi.SpiOff(pin, 255)
    s = RB0PPS + RB1PPS + RB2PPS + RB3PPS + RB4PPS + RB5PPS + RB6PPS + RB7PPS + RC0PPS + RC1PPS + RC2PPS + RC3PPS + RC4PPS + RC5PPS + RC6PPS + RC7PPS
    If s <> 0 Then
        Inc(badoff)
    End If
    sck = 8
    If pin = 8 Then
        sck = 9
    End If
    sdi = 22
    If pin = 22 Then
        sdi = 23
    End If
    ok = Spi.SpiInit(1000000, 0, sck, pin, sdi)
    Inc(n)
    v = 0
    If pin = 8 Then
        v = RB0PPS
    ElseIf pin = 9 Then
        v = RB1PPS
    ElseIf pin = 10 Then
        v = RB2PPS
    ElseIf pin = 11 Then
        v = RB3PPS
    ElseIf pin = 12 Then
        v = RB4PPS
    ElseIf pin = 13 Then
        v = RB5PPS
    ElseIf pin = 14 Then
        v = RB6PPS
    ElseIf pin = 15 Then
        v = RB7PPS
    ElseIf pin = 16 Then
        v = RC0PPS
    ElseIf pin = 17 Then
        v = RC1PPS
    ElseIf pin = 18 Then
        v = RC2PPS
    ElseIf pin = 19 Then
        v = RC3PPS
    ElseIf pin = 20 Then
        v = RC4PPS
    ElseIf pin = 21 Then
        v = RC5PPS
    ElseIf pin = 22 Then
        v = RC6PPS
    ElseIf pin = 23 Then
        v = RC7PPS
    End If
    s = RB0PPS + RB1PPS + RB2PPS + RB3PPS + RB4PPS + RB5PPS + RB6PPS + RB7PPS + RC0PPS + RC1PPS + RC2PPS + RC3PPS + RC4PPS + RC5PPS + RC6PPS + RC7PPS
    If ok <> 1 Or v <> 16 Or s <> 31 Then
        Inc(bad)
    End If
    Spi.SpiOff(sck, pin)
    s = RB0PPS + RB1PPS + RB2PPS + RB3PPS + RB4PPS + RB5PPS + RB6PPS + RB7PPS + RC0PPS + RC1PPS + RC2PPS + RC3PPS + RC4PPS + RC5PPS + RC6PPS + RC7PPS
    If s <> 0 Then
        Inc(badoff)
    End If
Next
