Program T
Device = 18F27Q10
Structure TStatus
    Val As Byte
    Enabled As Val.0
    Connected As Val.1
End Structure
Structure TPoint
    X As Word
    Y As Word
    Tag As String(4)
    Hist(3) As Byte
End Structure
Dim st As TStatus
Dim p As TPoint
Dim pts(4) As TPoint
st.Val = 0
st.Enabled = 1
p.X = 100
pts(2).Y = p.X + 1
p.Hist(1) = 7
Clear(p)
