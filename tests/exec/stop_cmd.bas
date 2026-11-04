' expect: ST_ST_A=1 ST_ST_B=7 ST_ST_C=3
' Stop is Terminate under another name. The harness needs the run to reach __halt, so the Stop that is
' compiled here are not taken.
Program St
Device = 18F27Q10
Clock = 64
Config FEXTOSC = OFF, RSTOSC = HFINTOSC_64MHZ, WDTE = OFF, LVP = ON
Dim st_a As Byte
Dim st_b As Byte
Dim st_c As Byte
st_a = 1
st_b = 7
st_c = 3
If st_b = 0 Then
    Stop
    st_c = 9
End If
If st_b = 1 Then
    Stop()
End If
