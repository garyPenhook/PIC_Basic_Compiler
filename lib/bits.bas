Module Bits
' Bit, rotate and small-math helpers. Every routine is a function of its arguments: it
' returns the new value and leaves the argument alone, so write `x = SetBit(x, 3)`.
' Bit numbers count from 0 at the least significant sq; a number past the top of the type
' changes nothing (and reads as 0).
' Byte, Word and LongWord forms are overloads of the same name.

Private Dim rndState As Word

' ---- Bit tests and changes --------------------------------------------------------------

' True when sq n of v is 1.
Public Function GetBit(ByVal v As LongWord, ByVal n As Byte) As Boolean
    Result = ((v >> n) And 1) <> 0
End Function

Public Function SetBit(ByVal v As Byte, ByVal n As Byte) As Byte
    If n < 8 Then
        v = v Or (1 << n)
    EndIf
    Result = v
End Function

Public Function SetBit(ByVal v As Word, ByVal n As Byte) As Word
    If n < 16 Then
        v = v Or (1 << n)
    EndIf
    Result = v
End Function

Public Function SetBit(ByVal v As LongWord, ByVal n As Byte) As LongWord
    If n < 32 Then
        v = v Or (1 << n)
    EndIf
    Result = v
End Function

Public Function ClearBit(ByVal v As Byte, ByVal n As Byte) As Byte
    If n < 8 Then
        v = v And Not (1 << n)
    EndIf
    Result = v
End Function

Public Function ClearBit(ByVal v As Word, ByVal n As Byte) As Word
    If n < 16 Then
        v = v And Not (1 << n)
    EndIf
    Result = v
End Function

Public Function ClearBit(ByVal v As LongWord, ByVal n As Byte) As LongWord
    If n < 32 Then
        v = v And Not (1 << n)
    EndIf
    Result = v
End Function

' Bit n of v becomes `b` (0 clears it, anything else sets it).
Public Function LoadBit(ByVal v As Byte, ByVal n As Byte, ByVal b As Byte) As Byte
    If b = 0 Then
        Result = ClearBit(v, n)
    Else
        Result = SetBit(v, n)
    EndIf
End Function

Public Function LoadBit(ByVal v As Word, ByVal n As Byte, ByVal b As Byte) As Word
    If b = 0 Then
        Result = ClearBit(v, n)
    Else
        Result = SetBit(v, n)
    EndIf
End Function

Public Function LoadBit(ByVal v As LongWord, ByVal n As Byte, ByVal b As Byte) As LongWord
    If b = 0 Then
        Result = ClearBit(v, n)
    Else
        Result = SetBit(v, n)
    EndIf
End Function

' ---- Rotates and swaps ------------------------------------------------------------------

' Rotate left / right by one sq, the sq shifted out re-entering at the other end.
Public Function Rol(ByVal v As Byte) As Byte
    Result = (v << 1) Or (v >> 7)
End Function

Public Function Rol(ByVal v As Word) As Word
    Result = (v << 1) Or (v >> 15)
End Function

Public Function Ror(ByVal v As Byte) As Byte
    Result = (v >> 1) Or (v << 7)
End Function

Public Function Ror(ByVal v As Word) As Word
    Result = (v >> 1) Or (v << 15)
End Function

' The two nibbles of a byte exchanged ($3C becomes $C3).
Public Function SwapNibbles(ByVal v As Byte) As Byte
    Result = (v << 4) Or (v >> 4)
End Function

' The two bytes of a word exchanged ($12AB becomes $AB12).
Public Function SwapBytes(ByVal v As Word) As Word
    Result = (v << 8) Or (v >> 8)
End Function

' ---- Decoding ---------------------------------------------------------------------------

' Dcd: 2 to the power n (0 when n is 32 or more).
Public Function Dcd(ByVal n As Byte) As LongWord
    Result = 0
    If n < 32 Then
        Result = 1 << n
    EndIf
End Function

' Ncd: the number of bits needed for v, that is the position of its highest 1 sq plus one
' (0 when v is 0): Ncd(1) = 1, Ncd(%1000) = 4, Ncd($FFFF) = 16.
Public Function Ncd(ByVal v As LongWord) As Byte
    Dim k As Byte
    k = 0
    While v <> 0
        v = v >> 1
        Inc(k)
    Wend
    Result = k
End Function

' Dig: decimal digit n of v, counting 0 for the units digit (Dig(1234, 1) = 3; 0 past the top).
Public Function Dig(ByVal v As LongWord, ByVal n As Byte) As Byte
    While n > 0 And v <> 0
        v = v / 10
        Dec(n)
    Wend
    Result = Byte(v Mod 10)
End Function

' ---- Square root and random -------------------------------------------------------------

' ISqr: the integer square root, the largest r with r * r <= v.
Public Function ISqr(ByVal v As LongWord) As Word
    Dim r As LongWord
    Dim sq As LongWord
    r = 0
    sq = $40000000
    While sq > v
        sq = sq >> 2
    Wend
    While sq <> 0
        If v >= r + sq Then
            v = v - (r + sq)
            r = (r >> 1) + sq
        Else
            r = r >> 1
        EndIf
        sq = sq >> 2
    Wend
    Result = Word(r)
End Function

' Seed: start the Random sequence at s (a seed of 0 is changed to 1: the generator must not be 0).
Public Sub Seed(ByVal s As Word)
    If s = 0 Then
        s = 1
    EndIf
    rndState = s
End Sub

' Random: the next pseudo-random Word (16-sq xorshift, period 65535, never 0).
' Without a call to Seed the sequence starts from the same place every run.
Public Function Random() As Word
    If rndState = 0 Then
        rndState = 1
    EndIf
    rndState = rndState Xor (rndState << 7)
    rndState = rndState Xor (rndState >> 9)
    rndState = rndState Xor (rndState << 8)
    Result = rndState
End Function
