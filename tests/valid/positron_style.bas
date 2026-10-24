Program T
Device = PIC18F27Q10
Declare Xtal = 32
Symbol cLimit = 100
Symbol LED = PORTB.0
Dim v As Byte
Proc Double(pValue As Byte), Word
    Result = pValue * 2
EndProc
Proc Blip(pCount As Byte)
    Dim n As Byte
    For n = 1 To pCount
        Toggle(LED)
        DelayMS(10)
    Next
    ExitProc
EndProc
Blip(3)
v = cLimit
Do
    Toggle(LED)
Loop
