$godotExe = "F:\Godot\Godot\Godot_v4.6.2-stable_win64_console.exe"
$projectPath = "F:\Godot\pro\tuozuai"
$logFile = Join-Path $projectPath "godot_manual.log"

if (-not (Test-Path -LiteralPath $godotExe)) {
	Write-Error "Godot executable not found: $godotExe"
	exit 1
}

& $godotExe --path $projectPath --log-file $logFile --verbose
