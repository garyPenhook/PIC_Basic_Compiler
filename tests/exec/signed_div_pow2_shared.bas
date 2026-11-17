' Balanced/Size shared signed divider: host-calculated sums of edge-case quotients.
' expect: DS_I1=4294936466 DS_I2=4294951882 DS_I3=4294959590 DS_I4=4294963444
' expect: DS_I5=4294965371 DS_I6=4294966335 DS_I7=4294966816 DS_I8=4294967057
' expect: DS_L1=4278107793 DS_L2=4286537545 DS_L3=4290752421 DS_L4=4292859859
' expect: DS_L5=4293913578 DS_L6=4294440438 DS_L7=4294703867 DS_L8=4294835582
Program DS
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Const IV(32) As Integer = (-32768, -32767, -16385, -16384, -8193, -8192, -4097, -4096, -1025, -1024, -513, -512, -257, -256, -255, -129, -128, -127, -33, -32, -31, -9, -8, -7, -1, 0, 1, 7, 8, 9, 32766, 32767)
Const LV(32) As LongInt = (-2147483648, -2147483647, -16777217, -16777216, -65537, -65536, -32769, -32768, -32767, -257, -256, -255, -129, -128, -127, -33, -32, -31, -9, -8, -7, -1, 0, 1, 7, 8, 9, 255, 256, 65535, 2147483646, 2147483647)
Dim i As Byte
Dim ivalue As Integer
Dim lvalue As LongInt
Volatile Dim I1, I2, I3, I4, I5, I6, I7, I8 As LongInt
Volatile Dim L1, L2, L3, L4, L5, L6, L7, L8 As LongInt
For i = 0 To 31
    ivalue = IV(i)
    lvalue = LV(i)
    I1 = I1 + LongInt(ivalue / 2)
    I2 = I2 + LongInt(ivalue / 4)
    I3 = I3 + LongInt(ivalue / 8)
    I4 = I4 + LongInt(ivalue / 16)
    I5 = I5 + LongInt(ivalue / 32)
    I6 = I6 + LongInt(ivalue / 64)
    I7 = I7 + LongInt(ivalue / 128)
    I8 = I8 + LongInt(ivalue / 256)
    L1 = L1 + LongInt(lvalue / 2)
    L2 = L2 + LongInt(lvalue / 4)
    L3 = L3 + LongInt(lvalue / 8)
    L4 = L4 + LongInt(lvalue / 16)
    L5 = L5 + LongInt(lvalue / 32)
    L6 = L6 + LongInt(lvalue / 64)
    L7 = L7 + LongInt(lvalue / 128)
    L8 = L8 + LongInt(lvalue / 256)
Next
