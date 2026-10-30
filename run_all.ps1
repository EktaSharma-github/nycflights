# NYCFlights - rebuild everything from the CSVs in data/ (about 1 minute).
#   powershell -ExecutionPolicy Bypass -File run_all.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$psql = "C:\Program Files\PostgreSQL\18\bin\psql.exe"
if (-not $env:PGPASSWORD) { $env:PGPASSWORD = "postgres" }
$db = "nycflights"

function Run-Sql($file, $out) {
    Write-Host "== $file"
    if ($out) { & $psql -h localhost -U postgres -d $db -v ON_ERROR_STOP=1 -q -f $file | Out-File -Encoding utf8 $out }
    else      { & $psql -h localhost -U postgres -d $db -v ON_ERROR_STOP=1 -q -f $file }
    if ($LASTEXITCODE -ne 0) { throw "$file failed" }
}

$exists = & $psql -h localhost -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$db'"
if (-not $exists) { & $psql -h localhost -U postgres -d postgres -c "CREATE DATABASE $db" }

Run-Sql 02_ddl.sql
Run-Sql 03_logic.sql
Write-Host "== 04_load.py"
& .\.venv\Scripts\python 04_load.py
if ($LASTEXITCODE -ne 0) { throw "04_load.py failed" }

New-Item -ItemType Directory -Force results | Out-Null
Run-Sql 05_queries.sql results\05_queries.txt
Run-Sql 06_demo.sql    results\06_demo.txt
Write-Host "Done. Query output is in results\"
