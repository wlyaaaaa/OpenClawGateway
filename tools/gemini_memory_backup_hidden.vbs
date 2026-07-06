' ============================================================
'  Hidden launcher for scheduled task "Gemini Memory Backup".
'  Window mode 0 = hidden; wait until PowerShell finishes.
' ============================================================
Dim fso, here, shell, exitCode
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
Set shell = CreateObject("WScript.Shell")
exitCode = shell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\backup-gemini-memory.ps1""", 0, True)
WScript.Quit exitCode
