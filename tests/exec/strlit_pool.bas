' expect: T_TOTAL=136 T_HITS=1 T_EMPTY=1 T_LENS=313 T_LAST=2
' String literals passed to a ByRefConst parameter that is also given a RAM string (so the literals keep RAM copies):
' the copies share one block filled by one start-up table copy (opt::pool_literals), each at its own offset with its
' Null. A wrong offset or a missing Null changes the lengths and the comparison. The two long literals make the block
' longer than 255 bytes, so it is copied in two pieces.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "strings"
Dim buf As String(8)
Dim total As Word
Dim hits As Byte
Dim empty As Byte
Dim lens As Word
Dim last As Byte

Sub Acc(ByRefConst s As String(16))
    total = total * 7 + Len(s)
    If s = "hello" Then
        hits = hits + 1
    End If
    If Len(s) = 0 Then
        empty = empty + 1
    End If
End Sub

Sub Longer(ByRefConst s As String(200))
    lens = lens + Len(s)
    last = 0
    If Right$(s, 1) = "z" Then
        last = 1
    ElseIf Right$(s, 1) = "y" Then
        last = 2
    End If
End Sub

buf = "xyz"
Acc("ab")
Acc("hello")
Acc(buf)
Acc("")
total = total / 7
Longer("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaz")
Longer("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbby")
Longer(buf)
Longer("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbby")
lens = lens - 160
