' Unary Not and negate stored through W or in place, sign-extended operands folded into a wider variable,
' signed and unsigned compares with a constant, and a Byte compare whose left side needs code.
' expect: T_N0=3989547399 T_N1=3989547400 T_N2=16656 T_N3=16657 T_N4=4278255360 T_N5=4294901760 T_N6=0 T_N7=166 T_N8=165 T_ACC=1000252 T_XR=284 T_SB=4748 T_C0=104 T_C1=112 T_C2=103 T_C3=113 T_U0=24 T_U1=16 T_B0=30 T_B1=26 T_B2=24 T_B3=32
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim N0, N1, N4, N5 As LongWord
Dim N2, N3, N6 As Word
Dim N7, N8 As Byte
Dim ACC, XR, SB As LongInt
Dim C0, C1, C2, C3, U0, U1, B0, B1, B2, B3 As Word
Dim V(18) As Integer = (0, 1, -1, 255, 256, -256, 32767, -32768, 1234, -1234, 4096, 4095, -4096, -4097, 2000, -2000, 2001, -2001)
Dim UV(10) As Word = (0, 255, 256, 4095, 4096, 4097, 65535, 4096, 4095, 32768)
Dim AR(8) As Byte = (3, 200, 17, 255, 0, 128, 127, 64)
Dim KY(7) As Byte = (0, 1, 64, 127, 128, 200, 255)
Dim L As LongWord
Dim W As Word
Dim Bt As Byte
Dim s As Integer
Dim u As Word
Dim i, j, key As Byte

Sub Unary()
    L = $12345678
    N0 = Not L
    N1 = 0 - L
    W = $BEEF
    N2 = Not W
    N3 = 0 - W
    N4 = $00FF00FF
    N4 = Not N4
    N5 = $00010000
    N5 = 0 - N5
    N6 = 0
    N6 = 0 - N6
    Bt = $5A
    N7 = 0 - Bt
    N8 = Not Bt
End Sub

Sub Signed()
    If s < 2000 Then
        C0 = C0 + 1
    End If
    If s >= 2000 Then
        C1 = C1 + 1
    End If
    If s > 2000 Then
        C2 = C2 + 1
    End If
    If s <= 2000 Then
        C3 = C3 + 1
    End If
    If s < -2000 Then
        C0 = C0 + 1
    End If
    If s >= -2000 Then
        C1 = C1 + 1
    End If
    If s > -2000 Then
        C2 = C2 + 1
    End If
    If s <= -2000 Then
        C3 = C3 + 1
    End If
    If s < 4096 Then
        C0 = C0 + 1
    End If
    If s >= 4096 Then
        C1 = C1 + 1
    End If
    If s > 4096 Then
        C2 = C2 + 1
    End If
    If s <= 4096 Then
        C3 = C3 + 1
    End If
    If s < -4096 Then
        C0 = C0 + 1
    End If
    If s >= -4096 Then
        C1 = C1 + 1
    End If
    If s > -4096 Then
        C2 = C2 + 1
    End If
    If s <= -4096 Then
        C3 = C3 + 1
    End If
    If s < 256 Then
        C0 = C0 + 1
    End If
    If s >= 256 Then
        C1 = C1 + 1
    End If
    If s > 256 Then
        C2 = C2 + 1
    End If
    If s <= 256 Then
        C3 = C3 + 1
    End If
    If s < -256 Then
        C0 = C0 + 1
    End If
    If s >= -256 Then
        C1 = C1 + 1
    End If
    If s > -256 Then
        C2 = C2 + 1
    End If
    If s <= -256 Then
        C3 = C3 + 1
    End If
    If s < 1 Then
        C0 = C0 + 1
    End If
    If s >= 1 Then
        C1 = C1 + 1
    End If
    If s > 1 Then
        C2 = C2 + 1
    End If
    If s <= 1 Then
        C3 = C3 + 1
    End If
    If s < -1 Then
        C0 = C0 + 1
    End If
    If s >= -1 Then
        C1 = C1 + 1
    End If
    If s > -1 Then
        C2 = C2 + 1
    End If
    If s <= -1 Then
        C3 = C3 + 1
    End If
    If s < 32767 Then
        C0 = C0 + 1
    End If
    If s >= 32767 Then
        C1 = C1 + 1
    End If
    If s > 32767 Then
        C2 = C2 + 1
    End If
    If s <= 32767 Then
        C3 = C3 + 1
    End If
    If s < -32767 Then
        C0 = C0 + 1
    End If
    If s >= -32767 Then
        C1 = C1 + 1
    End If
    If s > -32767 Then
        C2 = C2 + 1
    End If
    If s <= -32767 Then
        C3 = C3 + 1
    End If
    If s < 4660 Then
        C0 = C0 + 1
    End If
    If s >= 4660 Then
        C1 = C1 + 1
    End If
    If s > 4660 Then
        C2 = C2 + 1
    End If
    If s <= 4660 Then
        C3 = C3 + 1
    End If
    If s < -4660 Then
        C0 = C0 + 1
    End If
    If s >= -4660 Then
        C1 = C1 + 1
    End If
    If s > -4660 Then
        C2 = C2 + 1
    End If
    If s <= -4660 Then
        C3 = C3 + 1
    End If
End Sub

Sub Unsigned()
    If u < 256 Then
        U0 = U0 + 1
    End If
    If u >= 256 Then
        U1 = U1 + 1
    End If
    If u < 4096 Then
        U0 = U0 + 1
    End If
    If u >= 4096 Then
        U1 = U1 + 1
    End If
    If u < 32768 Then
        U0 = U0 + 1
    End If
    If u >= 32768 Then
        U1 = U1 + 1
    End If
    If u < 65280 Then
        U0 = U0 + 1
    End If
    If u >= 65280 Then
        U1 = U1 + 1
    End If
End Sub

Unary()
ACC = 1000000
SB = 5000
For i = 0 To 17
    s = V(i)
    ACC = ACC + s
    XR = XR Xor s
    SB = SB - s
    Signed()
Next
For i = 0 To 9
    u = UV(i)
    Unsigned()
Next
For j = 0 To 6
    key = KY(j)
    For i = 0 To 7
        If AR(i) >= key Then
            B0 = B0 + 1
        End If
        If AR(i) < key Then
            B1 = B1 + 1
        End If
        If AR(i) > key Then
            B2 = B2 + 1
        End If
        If AR(i) <= key Then
            B3 = B3 + 1
        End If
    Next
Next
