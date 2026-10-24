Program T
Device = 18F27Q10
Dim b As Byte
Asm Preserves(W, STATUS, BSR)
    movlw 0x55            ; a comment with 'quote
    xorwf PORTB, f, c
End Asm
b = 1
