' expect: E-ARGS
' says: help: missing `b As Byte`
' says: note: `Foo(a As Byte, b As Byte)` is declared here
Program T
Device = 18F27Q10
Sub Foo(a As Byte, b As Byte)
End Sub
Foo(1)
End
