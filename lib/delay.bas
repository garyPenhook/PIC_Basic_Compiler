Module Delay
' Delays beyond what the intrinsics cover. `DelayUs(n)` and `DelayMs(n)` are compiler
' intrinsics: cycle-counted from `Clock`, so they run longer when an interrupt hits them.

Public Sub DelaySeconds(ByVal s As Byte)
    ' Counts s down to 0: no loop variable and no copy of the limit.
    While s <> 0
        DelayMs(1000)
        s = s - 1
    Wend
End Sub

' A short fixed pause: the call, one `nop` and the return (5 instruction cycles). Inline
' `Asm nop End Asm` where exactly one cycle is wanted.
Public Sub DelayNop()
    Asm
        nop
    End Asm
End Sub
