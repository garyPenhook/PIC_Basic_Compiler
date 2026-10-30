Module Strings
' String helpers. A String is Null-terminated, so these walk it; the source is `ByRefConst`
' and takes a String of any size or a literal.

' Characters before the Null (0 for the empty string, at most 255).
Public Function Len(ByRefConst s As String) As Byte
    Dim k As Byte
    k = 0
    While s(k) <> #0
        Inc(k)
    Wend
    Result = k
End Function
