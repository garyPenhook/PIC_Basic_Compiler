Module Delay
' Delays beyond what the intrinsics cover. `DelayUs(n)` and `DelayMs(n)` are compiler
' intrinsics: cycle-counted from `Clock`, so they run longer when an interrupt hits them.

Public Sub DelaySeconds(ByVal s As Byte)
    Dim i As Byte
    For i = 1 To s
        DelayMs(1000)
    Next
End Sub

' One instruction cycle.
Public Sub DelayNop()
    Asm
        nop
    End Asm
End Sub
