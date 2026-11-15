' expect: T_A1=14 T_A2=14 T_A3=14 T_A4=99 T_A5=12 T_A6=0 T_A7=1 T_A8=7 T_A9=14 T_B1=14 T_B2=55 T_B3=1 T_B4=33 T_B5=9 T_B6=9 T_B7=30 T_B8=1
' expect-O0: T_A1=14 T_A2=14 T_A3=14 T_A4=99 T_A5=12 T_A6=0 T_A7=1 T_A8=7 T_A9=14 T_B1=14 T_B2=55 T_B3=1 T_B4=33 T_B5=9 T_B6=9 T_B7=30 T_B8=1
' `#option BoundsCheck = true`: a run-time index outside the array is clamped to the last element (a negative one
' too), for reads and writes, Byte, Word, LongWord and signed indexes, strings, packed bit arrays, two dimensions,
' an index that calls a function (worked out once), and ByRef / ByRefConst array parameters (their run-time length). `guard` after the array is never written.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
#option BoundsCheck = true
Dim a1 As Byte
Dim a2 As Byte
Dim a3 As Byte
Dim a4 As Byte
Dim a5 As Byte
Dim a6 As Byte
Dim a7 As Byte
Dim a8 As Byte
Dim a9 As Byte
Dim b1 As Byte
Dim b2 As Byte
Dim b3 As Byte
Dim b4 As Byte
Dim arr(5) As Byte
Dim guard As Byte
Dim i As Byte
Dim j As ShortInt
Dim w As Word
Dim l As LongWord
Dim s As String(4)
Dim f(10) As Bit
Dim m(2, 3) As Byte
Dim calls As Byte
Dim b5 As Byte
Dim b6 As Byte
Dim b7 As Byte
Dim b8 As Byte
Dim small(3) As Byte
Const tab(4) As Byte = (0, 10, 20, 30)

Sub Put(ByRef a() As Byte, k As Word)
    a(k) = 9
End Sub

Function Get(ByRefConst a() As Byte, k As Byte) As Byte
    Result = a(k)
End Function

Function Pick() As Byte
    calls = calls + 1
    Result = 9
End Function

For i = 0 To 4
    arr(i) = 10 + i
Next
guard = 55
i = 7
a1 = arr(i)
j = -1
a2 = arr(j)
w = 300
a3 = arr(w)
l = 65538
a9 = arr(l)
i = 2
a5 = arr(i)
s = "abcd"
i = 9
a6 = Byte(s(i))
i = 15
f(i) = 1
a7 = f(9)
m(1, 2) = 7
i = 5
a8 = m(i, i)
b1 = arr(Pick())
b3 = calls
If arr(i) = 14 Then
    b4 = 33
End If
i = 200
arr(i) = 99
a4 = arr(4)
b2 = guard
small(0) = 1
small(1) = 2
small(2) = 3
Put(small, 1000)
b5 = small(2)
b8 = small(0)
b6 = Get(small, 200)
b7 = Get(tab, 7)
End
