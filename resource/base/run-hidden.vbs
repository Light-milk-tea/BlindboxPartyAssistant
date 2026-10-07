Option Explicit

If WScript.Arguments.Count < 1 Then
    WScript.Quit 1
End If

Dim fso, scriptDir, ps1, shell, cmd, i, arg, code
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(scriptDir, WScript.Arguments(0))

cmd = """C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """"
For i = 1 To WScript.Arguments.Count - 1
    arg = WScript.Arguments(i)
    cmd = cmd & " """ & Replace(arg, """", """""") & """"
Next

Set shell = CreateObject("WScript.Shell")
code = shell.Run(cmd, 0, True)
WScript.Quit code
