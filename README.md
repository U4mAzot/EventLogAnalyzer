# EventLogAnalyzer - analiza Dziennika zdarzeń Windows

Skrypt PowerShell, który przegląda Dziennik zdarzeń za technika i w kilka sekund
odpowiada na pytanie: **„co się działo z tym komputerem?”**. Przydaje się przy
zgłoszeniach typu „komputer sam się restartuje”, „program ciągle się wyłącza”
albo „wczoraj był niebieski ekran”.

## Funkcje

- Pobiera błędy krytyczne i błędy (opcjonalnie ostrzeżenia) z dzienników **System** i **Application**
- Rozpoznaje **znane problemy** i opisuje je po polsku:

| Zdarzenie | Znaczenie |
|-----------|-----------|
| Kernel-Power 41, EventLog 6008 | nagłe wyłączenie / utrata zasilania |
| WER-SystemErrorReporting 1001 | Blue Screen (BSOD) |
| disk 7, 51, 153 / Ntfs 55 | problemy z dyskiem lub systemem plików |
| Application Error 1000 / Application Hang 1002 | awarie i zawieszenia aplikacji |
| Service Control Manager 7000-7034 | usługi, które nie startują lub padają |
| WindowsUpdateClient 20 | nieudane aktualizacje |
| DNS-Client 1014 | problemy z DNS |

- Zestawienie **10 najczęściej powtarzających się błędów**
- Lista ostatnich 50 zdarzeń
- Raport HTML do dołączenia do zgłoszenia

## Użycie

```powershell
# Ostatnie 24 godziny, raport otwierany w przeglądarce
.\Get-EventLogReport.ps1 -Open

# Ostatni tydzień, razem z ostrzeżeniami
.\Get-EventLogReport.ps1 -Hours 168 -IncludeWarnings
```

## Przykładowy wynik

```
Komputer            : PC-01
Zakres              : 2026-10-13 10:00 - 2026-10-14 10:00
Zdarzenia krytyczne : 1
Błędy               : 23
Ostrzeżenia         : nie analizowano

Wykryte znane problemy:

Problem                                                Wystąpienia Ostatnio
-------                                                ----------- --------
Usługa nieoczekiwanie przestała działać                          4 2026-10-14 08:12
Nieoczekiwane wyłączenie komputera (utrata zasilania...)         1 2026-10-13 22:47
Awaria aplikacji                                                 1 2026-10-13 15:03
```

## Wymagania

- Windows 10 / 11, PowerShell 5.1+
- Nie wymaga uprawnień administratora (dzienniki System i Application są dostępne dla użytkownika)

## Wykorzystane umiejętności

- Diagnostyka Windows na podstawie Dziennika zdarzeń (Event Viewer)
- Znajomość kluczowych identyfikatorów zdarzeń (Event ID)
- Wydajne filtrowanie przez `Get-WinEvent -FilterHashtable`
- Grupowanie i agregacja danych (`Group-Object`), raport HTML
