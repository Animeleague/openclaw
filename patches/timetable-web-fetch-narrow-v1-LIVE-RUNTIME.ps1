$ErrorActionPreference = "Stop"

$NpmRoot = npm root -g
$Dist = Join-Path $NpmRoot "openclaw\dist"
$File = Join-Path $Dist "openclaw-tools-CIBcX9Ku.js"

$BankDir = "$env:USERPROFILE\Desktop\forge-web-fetch-bank-2026-08-24"
$Bank = Join-Path $BankDir "openclaw-tools-CIBcX9Ku.KNOWN-GOOD.js"
$ExpectedHash = "A2B93887AA43E263B978EDCAD73151092631CEA74E977358F69C600C7B2F390C"

Write-Host "`nForge timetable web_fetch LIVE PATCH"
Write-Host "Live bundle: $File"
Write-Host "Bank copy:   $Bank"

if (-not (Test-Path -LiteralPath $File)) {
    throw "STOP: live OpenClaw bundle not found: $File"
}

if (-not (Test-Path -LiteralPath $Bank)) {
    throw "STOP: known-good bank copy not found: $Bank"
}

$CurrentHash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
if ($CurrentHash -ne $ExpectedHash) {
    throw "STOP: live bundle hash changed. Expected $ExpectedHash but found $CurrentHash"
}

$BankHash = (Get-FileHash -LiteralPath $Bank -Algorithm SHA256).Hash
if ($BankHash -ne $ExpectedHash) {
    throw "STOP: bank copy hash does not match expected known-good hash. Expected $ExpectedHash but found $BankHash"
}

$Source = [System.IO.File]::ReadAllText($File)

$Pattern = 'if \(readable\?\.text\) \{\s*text = readable\.text;\s*title = readable\.title;\s*extractor = readable\.extractor;\s*\} else \{'
$Matches = [regex]::Matches($Source, $Pattern)

if ($Matches.Count -ne 1) {
    throw "STOP: expected exactly one Readability branch, found $($Matches.Count). No changes made."
}

$Replacement = @'
if (readable?.text) {
                            let timetableHandled = false;
                            try {
                                    const timetableUrl = new URL(finalUrl);
                                    const hostnameParts = timetableUrl.hostname.toLowerCase().split(".");
                                    const isAnimeLeagueTimetable = hostnameParts.length === 3 && [
                                            "spring",
                                            "summer",
                                            "autumn",
                                            "winter"
                                    ].includes(hostnameParts[0]) && hostnameParts[1].endsWith("animecon") && hostnameParts[2] === "com" && (timetableUrl.pathname === "/timetable" || timetableUrl.pathname === "/timetable/");
                                    const isMobileAppTimetableStub = isAnimeLeagueTimetable && readable.text.toLowerCase().includes("download the anime league mobile app to view the timetable");
                                    if (isMobileAppTimetableStub) {
                                            const desktopOpen = body.match(/<main\b[^>]*class=["'][^"']*\bhidden\b[^"']*\bmd:block\b[^"']*["'][^>]*>/i);
                                            const desktopStart = desktopOpen?.index ?? -1;
                                            const desktopEnd = desktopStart >= 0 ? body.indexOf("</main>", desktopStart + desktopOpen[0].length) : -1;
                                            if (desktopStart >= 0 && desktopEnd >= 0) {
                                                    const desktopHtml = body.slice(desktopStart, desktopEnd + 7).replace(/\bhidden\b\s*/i, "");
                                                    const timetable = await extractBasicHtmlContent({
                                                            html: desktopHtml,
                                                            extractMode: params.extractMode
                                                    });
                                                    if (timetable?.text) {
                                                            text = timetable.text;
                                                            title = timetable.title ?? readable.title;
                                                            extractor = "raw-html-timetable";
                                                            timetableHandled = true;
                                                    }
                                            }
                                    }
                            } catch {}
                            if (!timetableHandled) {
                                    text = readable.text;
                                    title = readable.title;
                                    extractor = readable.extractor;
                            }
                    } else {
'@

$Replacement = $Replacement.Replace("`r`n", "`n")

$Match = $Matches[0]
$Patched = $Source.Substring(0, $Match.Index) +
           $Replacement +
           $Source.Substring($Match.Index + $Match.Length)

[System.IO.File]::WriteAllText(
    $File,
    $Patched,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "`nPATCH APPLIED TO LIVE BUNDLE:"
Select-String -Path $File -SimpleMatch 'raw-html-timetable' -Context 5,5

Write-Host "`nLIVE BUNDLE SYNTAX CHECK:"
node --check $File

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nSYNTAX FAILED - restoring known-good bundle"
    Copy-Item -LiteralPath $Bank -Destination $File -Force
    throw "LIVE PATCH FAILED: syntax check failed. Known-good bundle restored."
}

$PatchedHash = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
$BankHashAfter = (Get-FileHash -LiteralPath $Bank -Algorithm SHA256).Hash

if ($BankHashAfter -ne $ExpectedHash) {
    Write-Host "`nBANK HASH CHANGED UNEXPECTEDLY - restoring live bundle from bank"
    Copy-Item -LiteralPath $Bank -Destination $File -Force
    throw "STOP: known-good bank changed unexpectedly. Live bundle restored."
}

Write-Host "`nLIVE PATCH SUCCESS"
Write-Host "Patched SHA256: $PatchedHash"
Write-Host "Bank SHA256:    $BankHashAfter"
Write-Host "`nKnown-good bank preserved."
Write-Host "Restart the OpenClaw Gateway before live-testing /timetable."
