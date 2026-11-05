' expect: K_SINK=2635437108
Program K
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON

Dim data(48) As Byte
Dim flags(64) As Byte
Dim sink As LongWord
Dim seed As Word

Function Rnd() As Byte
    seed = seed * 25 + 13849
    Result = seed >> 8
End Function

Sub Fill()
    Dim i As Byte
    For i = 0 To 47
        data(i) = Rnd()
    Next
End Sub

Sub BubbleSort()
    Dim i, j, t As Byte
    For i = 0 To 46
        For j = 0 To 46 - i
            If data(j) > data(j + 1) Then
                t = data(j)
                data(j) = data(j + 1)
                data(j + 1) = t
            End If
        Next
    Next
End Sub

Sub InsertionSortDesc()
    Dim i, j, k As Byte
    For i = 1 To 47
        k = data(i)
        j = i
        While j > 0
            If data(j - 1) >= k Then
                Break
            End If
            data(j) = data(j - 1)
            j = j - 1
        Wend
        data(j) = k
    Next
End Sub

Function BinSearch(ByVal key As Byte) As Byte
    Dim lo, hi, mid As Byte
    lo = 0
    hi = 47
    Result = 255
    While lo <= hi
        mid = (lo + hi) >> 1
        If data(mid) = key Then
            Result = mid
            Break
        ElseIf data(mid) < key Then
            lo = mid + 1
        Else
            If mid = 0 Then
                Break
            End If
            hi = mid - 1
        End If
    Wend
End Function

Function Crc16(ByVal n As Byte) As Word
    Dim i, j As Byte
    Dim crc, t As Word
    crc = $FFFF
    For i = 0 To n - 1
        t = data(i)
        t = t << 8
        crc = crc Xor t
        For j = 1 To 8
            If (crc And $8000) <> 0 Then
                crc = (crc << 1) Xor $1021
            Else
                crc = crc << 1
            End If
        Next
    Next
    Result = crc
End Function

Function Crc32(ByVal n As Byte) As LongWord
    Dim i, j As Byte
    Dim crc As LongWord
    crc = $FFFFFFFF
    For i = 0 To n - 1
        crc = crc Xor data(i)
        For j = 1 To 8
            If (crc And 1) <> 0 Then
                crc = (crc >> 1) Xor $EDB88320
            Else
                crc = crc >> 1
            End If
        Next
    Next
    Result = Not crc
End Function

Function Primes() As Byte
    Dim i, j, cnt As Byte
    For i = 0 To 63
        flags(i) = 1
    Next
    flags(0) = 0
    flags(1) = 0
    For i = 2 To 7
        If flags(i) <> 0 Then
            j = i * i
            While j < 64
                flags(j) = 0
                j = j + i
            Wend
        End If
    Next
    cnt = 0
    For i = 0 To 63
        cnt = cnt + flags(i)
    Next
    Result = cnt
End Function

Function Gcd(ByVal a As Word, ByVal b As Word) As Word
    Dim t As Word
    While b <> 0
        t = a Mod b
        a = b
        b = t
    Wend
    Result = a
End Function

Function Isqrt(ByVal n As LongWord) As Word
    Dim r, bt As LongWord
    r = 0
    bt = $40000000
    While bt > n
        bt = bt >> 2
    Wend
    While bt <> 0
        If n >= r + bt Then
            n = n - (r + bt)
            r = (r >> 1) + bt
        Else
            r = r >> 1
        End If
        bt = bt >> 2
    Wend
    Result = r
End Function

Function Fib(ByVal n As Byte) As LongWord
    Dim a, b, t As LongWord
    Dim i As Byte
    a = 0
    b = 1
    For i = 1 To n
        t = a + b
        a = b
        b = t
    Next
    Result = a
End Function

Function Collatz(ByVal n As Word) As Word
    Dim steps As Word
    steps = 0
    While n <> 1
        If (n And 1) = 0 Then
            n = n >> 1
        Else
            n = n * 3 + 1
        End If
        steps = steps + 1
    Wend
    Result = steps
End Function

Function Popcount(ByVal v As LongWord) As Byte
    Dim c As Byte
    c = 0
    While v <> 0
        c = c + (v And 1)
        v = v >> 1
    Wend
    Result = c
End Function

Function DigitSum(ByVal v As Word) As Byte
    Dim s As Byte
    s = 0
    While v > 0
        s = s + v Mod 10
        v = v / 10
    Wend
    Result = s
End Function

seed = 1234
Fill()
sink = Crc16(48)
BubbleSort()
sink = sink Xor Crc32(48)
sink = sink + BinSearch(data(20))
InsertionSortDesc()
sink = sink Xor Crc16(48)
sink = sink + Primes()
sink = sink + Gcd(4620, 1980) + Gcd(seed, 9973)
sink = sink + Isqrt(1000000) + Isqrt(sink)
sink = sink Xor Fib(40)
sink = sink + Collatz(27) + Collatz(871)
sink = sink + Popcount(sink) + DigitSum(sink)
