' expect: LSP_BAD=0 LSP_BADOFF=0 LSP_N=34
' Module review 23 (spi), PIC18F16Q41 at 64 MHz: every pin the host takes (RA0..RA5 except RA3, RB4..RB7, RC0..RC7) as SCK, then as SDO, is routed alone through RxyPPS (codes 27 and 28) and given back by SpiOff; the pin numbers are run-time values, so the comparison chain in SetPps runs in full.
Program Lsp
Device = 18F16Q41
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "spi"
Dim i As Byte
Dim pin As Byte
Dim sck As Byte
Dim sdi As Byte
Dim ok As Byte
Dim v As Byte
Dim s As Byte
Dim bad As Byte
Dim badoff As Byte
Dim n As Byte
Const Pins(17) As Byte = (0, 1, 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23)
bad = 0
badoff = 0
n = 0
For i = 0 To 16
    pin = Pins(i)
    sdi = 16
    If pin = 16 Then
        sdi = 17
    End If
    ok = Spi.SpiInit(1000000, 0, pin, 255, sdi)
    Inc(n)
    v = 0
    If pin = 0 Then
        v = RA0PPS
    ElseIf pin = 1 Then
        v = RA1PPS
    ElseIf pin = 2 Then
        v = RA2PPS
    ElseIf pin = 4 Then
        v = RA4PPS
    ElseIf pin = 5 Then
        v = RA5PPS
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
    s = RA0PPS + RA1PPS + RA2PPS + RA4PPS + RA5PPS + RB4PPS + RB5PPS + RB6PPS + RB7PPS + RC0PPS + RC1PPS + RC2PPS + RC3PPS + RC4PPS + RC5PPS + RC6PPS + RC7PPS
    If ok <> 1 Or v <> 27 Or s <> 27 Then
        Inc(bad)
    End If
    Spi.SpiOff(pin, 255)
    s = RA0PPS + RA1PPS + RA2PPS + RA4PPS + RA5PPS + RB4PPS + RB5PPS + RB6PPS + RB7PPS + RC0PPS + RC1PPS + RC2PPS + RC3PPS + RC4PPS + RC5PPS + RC6PPS + RC7PPS
    If s <> 0 Then
        Inc(badoff)
    End If
    sck = 18
    If pin = 18 Then
        sck = 19
    End If
    sdi = 20
    If pin = 20 Then
        sdi = 21
    End If
    ok = Spi.SpiInit(1000000, 0, sck, pin, sdi)
    Inc(n)
    v = 0
    If pin = 0 Then
        v = RA0PPS
    ElseIf pin = 1 Then
        v = RA1PPS
    ElseIf pin = 2 Then
        v = RA2PPS
    ElseIf pin = 4 Then
        v = RA4PPS
    ElseIf pin = 5 Then
        v = RA5PPS
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
    s = RA0PPS + RA1PPS + RA2PPS + RA4PPS + RA5PPS + RB4PPS + RB5PPS + RB6PPS + RB7PPS + RC0PPS + RC1PPS + RC2PPS + RC3PPS + RC4PPS + RC5PPS + RC6PPS + RC7PPS
    If ok <> 1 Or v <> 28 Or s <> 55 Then
        Inc(bad)
    End If
    Spi.SpiOff(sck, pin)
    s = RA0PPS + RA1PPS + RA2PPS + RA4PPS + RA5PPS + RB4PPS + RB5PPS + RB6PPS + RB7PPS + RC0PPS + RC1PPS + RC2PPS + RC3PPS + RC4PPS + RC5PPS + RC6PPS + RC7PPS
    If s <> 0 Then
        Inc(badoff)
    End If
Next
