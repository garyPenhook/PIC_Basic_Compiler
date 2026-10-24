Program T
Device = 18F27Q10
Dim i As Byte
Dim n As Word
While i < 10
    Inc(i)
    If i = 5 Then
        Continue
    EndIf
    If i = 8 Then
        Break
    EndIf
Wend
Repeat
    Dec(i)
Until i = 0
For n = 10 To 0 Step -2
    i = i + 1
Next
Do While i < 3
    Inc(i)
Loop
Do Until i = 0
    Dec(i)
Loop
Do
    Inc(i)
Loop Until i > 4
Do
    Dec(i)
Loop While i > 0
