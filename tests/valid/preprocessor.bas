Program T
Device = 18F27Q10
#define FAST
#ifdef FAST
Dim a As Byte
#else
Dim a As Word
#endif
#ifndef FAST
Dim never As Word
#endif
#option Optimize = Size
#option ISR_SHADOW = false
a = 1
