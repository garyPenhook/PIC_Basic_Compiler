Program T
Device = 18F27Q10
Dim a As Byte
again:
Inc(a)
If a < 5 GoTo again
GoTo done
done:
a = 0
