' expect: T_R=124 T_S=7
' A helper's parameter that becomes its caller's variable (coalesce_params) must not be renamed again when the
' caller's parameter in turn becomes its own caller's: Inner would then read a variable nothing sets. Each routine
' is called once, from a statement, and none reads its variable after the call.
Program T
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Volatile Dim r As Word
Volatile Dim s As Byte
' Inputs the optimiser cannot know.
Volatile Dim inw As Word
Volatile Dim inb As Byte
Function Inner(ByVal n As Word) As Word
    Result = n + 2
End Function
Function Middle(ByVal m As Word) As Word
    Result = Inner(m)
End Function
Function Outer() As Word
    Dim w As Word
    w = inw
    Result = Middle(w)
End Function
Sub Leaf(ByVal b As Byte)
    s = b + 1
End Sub
Sub Branch(ByVal c As Byte)
    Leaf(c)
End Sub
inw = 122
inb = 6
r = Outer()
Branch(inb)
