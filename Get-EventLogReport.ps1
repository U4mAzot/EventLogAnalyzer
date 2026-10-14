<#
.SYNOPSIS
    Analizuje Dziennik zdarzeń Windows i tworzy raport HTML z błędami z ostatnich godzin.

.DESCRIPTION
    Zamiast przeglądać setki wpisów w Podglądzie zdarzeń, skrypt:
      - pobiera błędy krytyczne i błędy (opcjonalnie ostrzeżenia) z dzienników System i Application,
      - rozpoznaje znane problemy (BSOD, nagłe wyłączenia, błędy dysku, awarie aplikacji, usługi, aktualizacje),
      - pokazuje najczęściej powtarzające się błędy,
      - generuje raport HTML, który można dołączyć do zgłoszenia.

.PARAMETER Hours
    Z ilu ostatnich godzin analizować zdarzenia. Domyślnie 24.

.PARAMETER IncludeWarnings
    Uwzględnia także ostrzeżenia (domyślnie tylko błędy i zdarzenia krytyczne).

.PARAMETER Open
    Otwiera raport w przeglądarce po wygenerowaniu.

.EXAMPLE
    .\Get-EventLogReport.ps1 -Open

.EXAMPLE
    .\Get-EventLogReport.ps1 -Hours 168 -IncludeWarnings
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 720)]
    [int]$Hours = 24,
    [switch]$IncludeWarnings,
    [switch]$Open,
    [string]$OutputFolder
)

# Domyślne ścieżki względem folderu skryptu (w PowerShell 5.1 $PSScriptRoot bywa pusty w bloku param)
if (-not $OutputFolder) { $OutputFolder = Join-Path $PSScriptRoot 'reports' }

# Znane zdarzenia, które warto od razu wyróżnić: klucz "Źródło|ID"
$knownIssues = @{
    'Microsoft-Windows-Kernel-Power|41'          = 'Nieoczekiwane wyłączenie komputera (utrata zasilania, zawieszenie, wymuszony restart)'
    'EventLog|6008'                              = 'Poprzednie zamknięcie systemu było nieoczekiwane'
    'Microsoft-Windows-WER-SystemErrorReporting|1001' = 'Blue Screen (BSOD) - komputer uległ awarii'
    'disk|7'                                     = 'Uszkodzony sektor na dysku - rozważ wymianę dysku'
    'disk|51'                                    = 'Błąd podczas operacji na dysku'
    'disk|153'                                   = 'Ponowienie operacji na dysku - możliwe problemy z dyskiem'
    'Ntfs|55'                                    = 'Uszkodzenie systemu plików - zalecane chkdsk'
    'Application Error|1000'                     = 'Awaria aplikacji'
    'Application Hang|1002'                      = 'Aplikacja przestała odpowiadać'
    'Service Control Manager|7000'               = 'Usługa nie uruchomiła się'
    'Service Control Manager|7001'               = 'Usługa nie uruchomiła się z powodu zależności'
    'Service Control Manager|7023'               = 'Usługa zakończyła działanie z błędem'
    'Service Control Manager|7031'               = 'Usługa nieoczekiwanie przestała działać'
    'Service Control Manager|7034'               = 'Usługa nieoczekiwanie przestała działać'
    'Microsoft-Windows-WindowsUpdateClient|20'   = 'Nieudana instalacja aktualizacji Windows'
    'Microsoft-Windows-DNS-Client|1014'          = 'Przekroczono czas rozpoznawania nazwy DNS'
    'Microsoft-Windows-Time-Service|129'         = 'Problem z synchronizacją czasu'
}

$levelNames = @{ 1 = 'Krytyczny'; 2 = 'Błąd'; 3 = 'Ostrzeżenie' }
$levels = @(1, 2)
if ($IncludeWarnings) { $levels += 3 }

$startTime = (Get-Date).AddHours(-$Hours)

Write-Host "Analiza dziennika zdarzeń z ostatnich $Hours godz. ..." -ForegroundColor Cyan

# --- Pobieranie zdarzeń -------------------------------------------------------------
$events = @()
foreach ($logName in 'System', 'Application') {
    try {
        $events += Get-WinEvent -FilterHashtable @{ LogName = $logName; Level = $levels; StartTime = $startTime } -ErrorAction Stop
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
            Write-Warning "Nie udało się odczytać dziennika $($logName): $($_.Exception.Message)"
        }
    }
}

$events = @($events | Sort-Object TimeCreated -Descending | ForEach-Object {
    $message = if ($_.Message) { ($_.Message -split "`r?`n")[0] } else { '(brak opisu)' }
    [pscustomobject]@{
        Czas       = $_.TimeCreated
        Dziennik   = $_.LogName
        Poziom     = $levelNames[[int]$_.Level]
        Źródło     = $_.ProviderName
        ID         = $_.Id
        Komunikat  = if ($message.Length -gt 160) { $message.Substring(0, 160) + '...' } else { $message }
        Klucz      = "$($_.ProviderName)|$($_.Id)"
    }
})

# --- Analiza ------------------------------------------------------------------------
$countBy = { param($level) @($events | Where-Object Poziom -eq $level).Count }
$summary = [pscustomobject][ordered]@{
    'Komputer'          = $env:COMPUTERNAME
    'Zakres'            = "$($startTime.ToString('yyyy-MM-dd HH:mm')) - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    'Zdarzenia krytyczne' = & $countBy 'Krytyczny'
    'Błędy'             = & $countBy 'Błąd'
    'Ostrzeżenia'       = if ($IncludeWarnings) { & $countBy 'Ostrzeżenie' } else { 'nie analizowano' }
}

$detected = @($events | Where-Object { $knownIssues.ContainsKey($_.Klucz) } |
    Group-Object Klucz | ForEach-Object {
        [pscustomobject]@{
            Problem    = $knownIssues[$_.Name]
            Źródło     = $_.Group[0].Źródło
            ID         = $_.Group[0].ID
            Wystąpienia = $_.Count
            Ostatnio   = $_.Group[0].Czas.ToString('yyyy-MM-dd HH:mm')
        }
    } | Sort-Object Wystąpienia -Descending)

$topErrors = @($events | Group-Object Klucz | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object {
    [pscustomobject]@{
        Liczba    = $_.Count
        Poziom    = $_.Group[0].Poziom
        Źródło    = $_.Group[0].Źródło
        ID        = $_.Group[0].ID
        Komunikat = $_.Group[0].Komunikat
    }
})

$recent = $events | Select-Object -First 50 |
    Select-Object @{ n = 'Czas'; e = { $_.Czas.ToString('yyyy-MM-dd HH:mm:ss') } }, Dziennik, Poziom, Źródło, ID, Komunikat

# --- Konsola ----------------------------------------------------------------------
Write-Host "`n$(($summary | Format-List | Out-String).Trim())`n"
if ($detected.Count -gt 0) {
    Write-Host 'Wykryte znane problemy:' -ForegroundColor Yellow
    Write-Host "$(($detected | Format-Table Problem, Wystąpienia, Ostatnio -AutoSize | Out-String).Trim())`n"
} else {
    Write-Host "Nie wykryto znanych problemów.`n" -ForegroundColor Green
}

# --- Raport HTML ------------------------------------------------------------------
$style = @'
<style>
  body  { font-family: Segoe UI, Arial, sans-serif; margin: 30px; background: #f4f6f9; color: #222; }
  h1    { color: #1f4e79; }
  h2    { color: #1f4e79; border-bottom: 2px solid #1f4e79; padding-bottom: 4px; margin-top: 30px; }
  table { border-collapse: collapse; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,.1); width: 100%; }
  th, td { border: 1px solid #dde3ea; padding: 6px 10px; text-align: left; font-size: 13px; vertical-align: top; }
  th    { background: #1f4e79; color: #fff; }
  tr:nth-child(even) td { background: #f8fafc; }
  .detected th { background: #b85c00; }
  .ok   { background: #e8f6ec; border-left: 5px solid #2e9e50; padding: 10px 15px; }
  .summary table { width: auto; }
</style>
'@

function ConvertTo-HtmlFragment($Data, [string]$EmptyText) {
    if (@($Data).Count -eq 0) { return "<div class='ok'>$EmptyText</div>" }
    $Data | ConvertTo-Html -Fragment
}

$html = @"
<!DOCTYPE html>
<html lang="pl">
<head><meta charset="utf-8"><title>Dziennik zdarzeń - $env:COMPUTERNAME</title>$style</head>
<body>
<h1>Raport dziennika zdarzeń: $env:COMPUTERNAME</h1>

<div class="summary">
<h2>Podsumowanie</h2>
$($summary | ConvertTo-Html -As List -Fragment)
</div>

<div class="detected">
<h2>Wykryte znane problemy</h2>
$(ConvertTo-HtmlFragment $detected '&#10004; Nie wykryto znanych problemów.')
</div>

<h2>Najczęstsze błędy (top 10)</h2>
$(ConvertTo-HtmlFragment $topErrors '&#10004; Brak błędów w wybranym okresie.')

<h2>Ostatnie zdarzenia (max 50)</h2>
$(ConvertTo-HtmlFragment $recent '&#10004; Brak zdarzeń w wybranym okresie.')
</body>
</html>
"@

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}
$reportPath = Join-Path $OutputFolder ("EventLog_{0}_{1}.html" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
$html | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host "Raport zapisany: $reportPath" -ForegroundColor Green

if ($Open) {
    Start-Process $reportPath
}
