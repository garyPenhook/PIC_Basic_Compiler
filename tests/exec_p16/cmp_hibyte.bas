' expect: CH_BAD=0
' Unsigned Word variable against a multiple of 256, or one less (`w < 256`, `w >= 512`, `w > 255`, `w <= 511`, and the
' constant on the left): only the high byte is tested. Each answer is checked against the same compare on a LongWord copy,
' which takes the four-byte path. CH_BAD counts the wrong answers.
Program Ch
Device = 16F17146
Clock = 32
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_32MHz, WDTE = OFF, LVP = ON
Dim w As Word
Dim l As LongWord
Dim bad As Word
Dim c1 As Byte
Dim c2 As Byte
Dim tot As Byte
Dim i As Byte
Dim tv(17) As Word

tv(0) = 0
tv(1) = 1
tv(2) = 255
tv(3) = 256
tv(4) = 257
tv(5) = 511
tv(6) = 512
tv(7) = 767
tv(8) = 768
tv(9) = 1023
tv(10) = 1024
tv(11) = 32767
tv(12) = 32768
tv(13) = 65279
tv(14) = 65280
tv(15) = 65281
tv(16) = 65535
For i = 0 To 16
    w = tv(i)
    l = w
    c1 = 0
    If w < 256 Then
        c1 = 1
    End If
    c2 = 0
    If l < 256 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w < 512 Then
        c1 = 1
    End If
    c2 = 0
    If l < 512 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w < 768 Then
        c1 = 1
    End If
    c2 = 0
    If l < 768 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w < 1024 Then
        c1 = 1
    End If
    c2 = 0
    If l < 1024 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w < 65280 Then
        c1 = 1
    End If
    c2 = 0
    If l < 65280 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w < 255 Then
        c1 = 1
    End If
    c2 = 0
    If l < 255 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w < 511 Then
        c1 = 1
    End If
    c2 = 0
    If l < 511 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w < 1023 Then
        c1 = 1
    End If
    c2 = 0
    If l < 1023 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w < 65279 Then
        c1 = 1
    End If
    c2 = 0
    If l < 65279 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w >= 256 Then
        c1 = 1
    End If
    c2 = 0
    If l >= 256 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w >= 512 Then
        c1 = 1
    End If
    c2 = 0
    If l >= 512 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w >= 768 Then
        c1 = 1
    End If
    c2 = 0
    If l >= 768 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w >= 1024 Then
        c1 = 1
    End If
    c2 = 0
    If l >= 1024 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w >= 65280 Then
        c1 = 1
    End If
    c2 = 0
    If l >= 65280 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w >= 255 Then
        c1 = 1
    End If
    c2 = 0
    If l >= 255 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w >= 511 Then
        c1 = 1
    End If
    c2 = 0
    If l >= 511 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w >= 1023 Then
        c1 = 1
    End If
    c2 = 0
    If l >= 1023 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w >= 65279 Then
        c1 = 1
    End If
    c2 = 0
    If l >= 65279 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w > 256 Then
        c1 = 1
    End If
    c2 = 0
    If l > 256 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w > 512 Then
        c1 = 1
    End If
    c2 = 0
    If l > 512 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w > 768 Then
        c1 = 1
    End If
    c2 = 0
    If l > 768 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w > 1024 Then
        c1 = 1
    End If
    c2 = 0
    If l > 1024 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w > 65280 Then
        c1 = 1
    End If
    c2 = 0
    If l > 65280 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w > 255 Then
        c1 = 1
    End If
    c2 = 0
    If l > 255 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w > 511 Then
        c1 = 1
    End If
    c2 = 0
    If l > 511 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w > 1023 Then
        c1 = 1
    End If
    c2 = 0
    If l > 1023 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w > 65279 Then
        c1 = 1
    End If
    c2 = 0
    If l > 65279 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w <= 256 Then
        c1 = 1
    End If
    c2 = 0
    If l <= 256 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w <= 512 Then
        c1 = 1
    End If
    c2 = 0
    If l <= 512 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w <= 768 Then
        c1 = 1
    End If
    c2 = 0
    If l <= 768 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w <= 1024 Then
        c1 = 1
    End If
    c2 = 0
    If l <= 1024 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w <= 65280 Then
        c1 = 1
    End If
    c2 = 0
    If l <= 65280 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w <= 255 Then
        c1 = 1
    End If
    c2 = 0
    If l <= 255 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w <= 511 Then
        c1 = 1
    End If
    c2 = 0
    If l <= 511 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w <= 1023 Then
        c1 = 1
    End If
    c2 = 0
    If l <= 1023 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If w <= 65279 Then
        c1 = 1
    End If
    c2 = 0
    If l <= 65279 Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 256 > w Then
        c1 = 1
    End If
    c2 = 0
    If 256 > l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 512 > w Then
        c1 = 1
    End If
    c2 = 0
    If 512 > l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 768 > w Then
        c1 = 1
    End If
    c2 = 0
    If 768 > l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 1024 > w Then
        c1 = 1
    End If
    c2 = 0
    If 1024 > l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 65280 > w Then
        c1 = 1
    End If
    c2 = 0
    If 65280 > l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 255 > w Then
        c1 = 1
    End If
    c2 = 0
    If 255 > l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 511 > w Then
        c1 = 1
    End If
    c2 = 0
    If 511 > l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 1023 > w Then
        c1 = 1
    End If
    c2 = 0
    If 1023 > l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 65279 > w Then
        c1 = 1
    End If
    c2 = 0
    If 65279 > l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 256 <= w Then
        c1 = 1
    End If
    c2 = 0
    If 256 <= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 512 <= w Then
        c1 = 1
    End If
    c2 = 0
    If 512 <= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 768 <= w Then
        c1 = 1
    End If
    c2 = 0
    If 768 <= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 1024 <= w Then
        c1 = 1
    End If
    c2 = 0
    If 1024 <= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 65280 <= w Then
        c1 = 1
    End If
    c2 = 0
    If 65280 <= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 255 <= w Then
        c1 = 1
    End If
    c2 = 0
    If 255 <= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 511 <= w Then
        c1 = 1
    End If
    c2 = 0
    If 511 <= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 1023 <= w Then
        c1 = 1
    End If
    c2 = 0
    If 1023 <= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 65279 <= w Then
        c1 = 1
    End If
    c2 = 0
    If 65279 <= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 256 < w Then
        c1 = 1
    End If
    c2 = 0
    If 256 < l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 512 < w Then
        c1 = 1
    End If
    c2 = 0
    If 512 < l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 768 < w Then
        c1 = 1
    End If
    c2 = 0
    If 768 < l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 1024 < w Then
        c1 = 1
    End If
    c2 = 0
    If 1024 < l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 65280 < w Then
        c1 = 1
    End If
    c2 = 0
    If 65280 < l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 255 < w Then
        c1 = 1
    End If
    c2 = 0
    If 255 < l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 511 < w Then
        c1 = 1
    End If
    c2 = 0
    If 511 < l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 1023 < w Then
        c1 = 1
    End If
    c2 = 0
    If 1023 < l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 65279 < w Then
        c1 = 1
    End If
    c2 = 0
    If 65279 < l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 256 >= w Then
        c1 = 1
    End If
    c2 = 0
    If 256 >= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 512 >= w Then
        c1 = 1
    End If
    c2 = 0
    If 512 >= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 768 >= w Then
        c1 = 1
    End If
    c2 = 0
    If 768 >= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 1024 >= w Then
        c1 = 1
    End If
    c2 = 0
    If 1024 >= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 65280 >= w Then
        c1 = 1
    End If
    c2 = 0
    If 65280 >= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 255 >= w Then
        c1 = 1
    End If
    c2 = 0
    If 255 >= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 511 >= w Then
        c1 = 1
    End If
    c2 = 0
    If 511 >= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 1023 >= w Then
        c1 = 1
    End If
    c2 = 0
    If 1023 >= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
    c1 = 0
    If 65279 >= w Then
        c1 = 1
    End If
    c2 = 0
    If 65279 >= l Then
        c2 = 1
    End If
    If c1 <> c2 Then
        bad = bad + 1
    End If
Next
tot = 1
