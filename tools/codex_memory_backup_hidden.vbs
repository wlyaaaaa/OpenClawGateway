' ============================================================
'  Hidden launcher for scheduled task "Codex Memory Backup".
'  Window mode 0 = hidden; wait and propagate the backup exit code.
' ============================================================
Dim fso, here, shell, exitCode
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
Set shell = CreateObject("WScript.Shell")
exitCode = shell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\backup-codex-memory.ps1""", 0, True)
WScript.Quit exitCode
