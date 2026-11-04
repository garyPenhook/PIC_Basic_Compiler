' expect: GL_GL_OK=1 GL_GL_BAD=0 GL_GL_TRIS=0 GL_GL_DONE=1
' Compiles and runs `Glcd` with the real `Pinio` (no display attached: the busy polls give up): the init takes the data port and the control pins.
Program Gl
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Include "glcd"
Dim gl_ok As Byte
Dim gl_bad As Byte
Dim gl_tris As Byte
Dim gl_done As Byte
gl_bad = Glcd.GlcdInitKs0108(0, 8, 9, 10, 11, 12, 13, True)
gl_ok = Glcd.GlcdInitKs0108(16, 8, 9, 10, 11, 12, 13, True)
Glcd.GlcdPlot(10, 10)
Glcd.GlcdLine(True, 0, 0, 20, 20)
Glcd.GlcdWrite("Hi")
gl_tris = TRISC And 255
gl_done = 1
