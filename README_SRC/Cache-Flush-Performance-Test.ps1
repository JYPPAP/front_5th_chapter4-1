# Cache-Flush-Performance-Test-Fixed.ps1
# URL ���� ���� ���� ����

param(
    [string]$S3Url = "http://jys-new-bucket.s3-website-ap-southeast-2.amazonaws.com/",
    [string]$CloudFrontUrl = "https://d18gdmgx2pxnac.cloudfront.net/",
    [int]$TestCount = 3
)

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "     ������ ĳ�� �ʱ�ȭ ���� �׽�Ʈ" -ForegroundColor Cyan  
Write-Host "===========================================" -ForegroundColor Cyan

# URL ��ȿ�� �˻� �Լ�
function Test-UrlValid {
    param([string]$TestUrl)
    
    try {
        $uri = [System.Uri]$TestUrl
        return $uri.IsAbsoluteUri
    }
    catch {
        return $false
    }
}

# ����� ���� ���
Write-Host "[DEBUG] URL ����:" -ForegroundColor Yellow
Write-Host "S3 URL: '$S3Url'" -ForegroundColor Gray
Write-Host "CloudFront URL: '$CloudFrontUrl'" -ForegroundColor Gray
Write-Host "S3 URL ��ȿ: $(Test-UrlValid $S3Url)" -ForegroundColor Gray
Write-Host "CloudFront URL ��ȿ: $(Test-UrlValid $CloudFrontUrl)" -ForegroundColor Gray
Write-Host ""

# ĳ�� �ʱ�ȭ �Լ�
function Clear-AllCaches {
    Write-Host "[FLUSH] ��� ĳ�� �ʱ�ȭ ��..." -ForegroundColor Yellow
    
    try {
        # 1. DNS ĳ�� �ʱ�ȭ
        Write-Host "   DNS ĳ�� �ʱ�ȭ..." -ForegroundColor Gray
        ipconfig /flushdns | Out-Null
        
        # 2. ��Ʈ��ũ ���� �ʱ�ȭ (������ ���� �ʿ��)
        Write-Host "   ��Ʈ��ũ ĳ�� �ʱ�ȭ..." -ForegroundColor Gray
        # netsh int ip reset | Out-Null  # �ʹ� ������ ��ɾ�� �ּ� ó��
        
        # 3. ��� ��� (DNS ����)
        Start-Sleep -Seconds 2
        
        Write-Host "   ĳ�� �ʱ�ȭ �Ϸ�!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "   ĳ�� �ʱ�ȭ ����: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   ������ �������� �����ϼ���" -ForegroundColor Yellow
        return $false
    }
}

# ���� Cold Start ���� �Լ� (������)
function Measure-ColdStart {
    param(
        [string]$BaseUrl,
        [string]$ServiceName
    )
    
    # URL ��ȿ�� ���� �˻�
    if (-not (Test-UrlValid $BaseUrl)) {
        Write-Host "   ����: �߸��� �⺻ URL - $BaseUrl" -ForegroundColor Red
        return @{
            Success = $false
            Error = "Invalid Base URL"
            TotalTimeMs = 0
        }
    }
    
    # ������ ���� �Ķ���ͷ� ĳ�� ��ȸ
    $timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    $randomGuid = [System.Guid]::NewGuid().ToString()
    
    # URL ������ �� �����ϰ� ó��
    if ($BaseUrl.EndsWith('/')) {
        $coldUrl = $BaseUrl + "?coldstart=$timestamp&random=$randomGuid"
    } else {
        $coldUrl = $BaseUrl + "/?coldstart=$timestamp&random=$randomGuid"
    }
    
    Write-Host "   Cold Start URL: $coldUrl" -ForegroundColor Gray
    
    # ������ URL �����
    if (-not (Test-UrlValid $coldUrl)) {
        Write-Host "   ����: �߸��� ���� URL - $coldUrl" -ForegroundColor Red
        return @{
            Success = $false
            Error = "Invalid Generated URL"
            TotalTimeMs = 0
        }
    }
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # ��� ĳ�� ��ȸ ���
        $headers = @{
            'Cache-Control' = 'no-cache, no-store, must-revalidate'
            'Pragma' = 'no-cache'
            'Expires' = '0'
        }
        
        $response = Invoke-WebRequest -Uri $coldUrl -Headers $headers -UseBasicParsing -TimeoutSec 30
        $stopwatch.Stop()
        
        # CloudFront ��� ����
        $xCache = ""
        $age = ""
        $via = ""
        
        if ($response.Headers) {
            if ($response.Headers.ContainsKey("X-Cache")) {
                $xCache = $response.Headers["X-Cache"] -join ", "
            }
            if ($response.Headers.ContainsKey("Age")) {
                $age = $response.Headers["Age"] -join ", "
            }
            if ($response.Headers.ContainsKey("Via")) {
                $via = $response.Headers["Via"] -join ", "
            }
        }
        
        return @{
            Success = $true
            TotalTimeMs = $stopwatch.ElapsedMilliseconds
            ResponseSize = $response.Content.Length
            StatusCode = $response.StatusCode
            XCache = $xCache
            Age = $age
            Via = $via
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
            TotalTimeMs = 0
        }
    }
}

# ������ Cold Start �� �Լ�
function Test-TrueColdStart {
    param(
        [string]$Url,
        [string]$ServiceName,
        [string]$Color
    )
    
    Write-Host "[$ServiceName] ������ Cold Start �׽�Ʈ" -ForegroundColor $Color
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "�⺻ URL: $Url" -ForegroundColor Gray
    
    $times = @()
    $cacheStatuses = @()
    
    for ($i = 1; $i -le $TestCount; $i++) {
        Write-Host "[$i/$TestCount] Cold Start ����..." -ForegroundColor Yellow
        
        # �� �׽�Ʈ���� ĳ�� �ʱ�ȭ (ù ��° ����)
        if ($i -gt 1) {
            Write-Host "   ĳ�� �ʱ�ȭ ��..." -ForegroundColor Gray
            Clear-AllCaches | Out-Null
        }
        
        $result = Measure-ColdStart -BaseUrl $Url -ServiceName $ServiceName
        
        if ($result.Success) {
            $times += $result.TotalTimeMs
            $cacheStatuses += $result.XCache
            
            Write-Host "   �� �ð�: $($result.TotalTimeMs) ms" -ForegroundColor Green
            Write-Host "   ���� ũ��: $($result.ResponseSize) bytes" -ForegroundColor Gray
            
            if ($ServiceName -eq "CloudFront") {
                Write-Host "   ĳ�� ����: $($result.XCache)" -ForegroundColor $(if($result.XCache -like "*Hit*") { "Green" } else { "Red" })
                if ($result.Age -ne "") {
                    Write-Host "   ĳ�� ����: $($result.Age) ��" -ForegroundColor Gray
                }
                if ($result.Via -ne "") {
                    Write-Host "   Via: $($result.Via)" -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "   ����: $($result.Error)" -ForegroundColor Red
        }
        
        Write-Host ""
        
        # �׽�Ʈ �� ����� ���
        if ($i -lt $TestCount) {
            Start-Sleep -Seconds 3
        }
    }
    
    if ($times.Count -gt 0) {
        $avg = ($times | Measure-Object -Average).Average
        $min = ($times | Measure-Object -Minimum).Minimum
        $max = ($times | Measure-Object -Maximum).Maximum
        
        Write-Host "[$ServiceName] ���:" -ForegroundColor $Color
        Write-Host "   ���: $([math]::Round($avg, 2)) ms" -ForegroundColor Green
        Write-Host "   �ּ�: $min ms" -ForegroundColor Gray
        Write-Host "   �ִ�: $max ms" -ForegroundColor Gray
        
        if ($ServiceName -eq "CloudFront") {
            $missCount = ($cacheStatuses | Where-Object { $_ -like "*Miss*" }).Count
            $hitCount = ($cacheStatuses | Where-Object { $_ -like "*Hit*" }).Count
            Write-Host "   ĳ�� Miss: $missCount ȸ" -ForegroundColor Red
            Write-Host "   ĳ�� Hit: $hitCount ȸ" -ForegroundColor Green
        }
        
        return $avg
    } else {
        Write-Host "[$ServiceName] ���� ����" -ForegroundColor Red
        return 0
    }
}

# ������ ���� �׽�Ʈ ���� ����
Write-Host "[CONNECT] �⺻ ���� �׽�Ʈ:" -ForegroundColor Yellow
try {
    Write-Host "S3 ���� �׽�Ʈ..." -ForegroundColor Gray
    $s3Test = Invoke-WebRequest -Uri $S3Url -UseBasicParsing -TimeoutSec 5
    Write-Host "S3 ���� ���� (����: $($s3Test.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "S3 ���� ����: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "��ũ��Ʈ�� �����մϴ�." -ForegroundColor Red
    exit 1
}

try {
    Write-Host "CloudFront ���� �׽�Ʈ..." -ForegroundColor Gray
    $cfTest = Invoke-WebRequest -Uri $CloudFrontUrl -UseBasicParsing -TimeoutSec 5
    Write-Host "CloudFront ���� ���� (����: $($cfTest.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "CloudFront ���� ����: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "��ũ��Ʈ�� �����մϴ�." -ForegroundColor Red
    exit 1
}

Write-Host ""

# ���� ĳ�� �ʱ�ȭ
Write-Host "[INIT] �ʱ� ĳ�� �ʱ�ȭ..." -ForegroundColor Cyan
$flushResult = Clear-AllCaches

if (-not $flushResult) {
    Write-Host "[WARNING] ĳ�� �ʱ�ȭ�� �����߽��ϴ�. ������ �������� �����ϸ� �� ��Ȯ�� ����� ���� �� �ֽ��ϴ�." -ForegroundColor Yellow
    Write-Host ""
}

# S3 Cold Start �׽�Ʈ
Write-Host ""
$s3Avg = Test-TrueColdStart -Url $S3Url -ServiceName "S3" -Color "Blue"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

# CloudFront Cold Start �׽�Ʈ  
$cfAvg = Test-TrueColdStart -Url $CloudFrontUrl -ServiceName "CloudFront" -Color "Red"

# ���� ��
Write-Host ""
Write-Host "[FINAL] ���� Cold Start �� ���" -ForegroundColor Magenta
Write-Host "===========================================" -ForegroundColor Cyan

if ($s3Avg -gt 0 -and $cfAvg -gt 0) {
    Write-Host "S3 Cold Start ���: $([math]::Round($s3Avg, 2)) ms" -ForegroundColor Blue
    Write-Host "CloudFront Cold Start ���: $([math]::Round($cfAvg, 2)) ms" -ForegroundColor Red
    
    $timeDiff = [math]::Abs($s3Avg - $cfAvg)
    Write-Host "�ð� ����: $([math]::Round($timeDiff, 2)) ms" -ForegroundColor Yellow
    
    if ($s3Avg -gt $cfAvg) {
        $improvement = ($s3Avg - $cfAvg) / $s3Avg * 100
        Write-Host "WINNER: CloudFront�� $([math]::Round($improvement, 1))% ����!" -ForegroundColor Green
    } elseif ($cfAvg -gt $s3Avg) {
        $improvement = ($cfAvg - $s3Avg) / $cfAvg * 100
        Write-Host "WINNER: S3�� $([math]::Round($improvement, 1))% ����!" -ForegroundColor Green
    } else {
        Write-Host "RESULT: ���� ������ ����" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "[INFO] �м�:" -ForegroundColor Cyan
    if ($timeDiff -lt 50) {
        Write-Host "   ���̰� 50ms �̸����� ��Ʈ��ũ ���� ���� �����Դϴ�." -ForegroundColor Gray
        Write-Host "   �� ���� �׽�Ʈ�� �ʿ��� �� �ֽ��ϴ�." -ForegroundColor Gray
    }
} else {
    Write-Host "������ �����߽��ϴ�." -ForegroundColor Red
}

Write-Host ""
Write-Host "[TIP] �� ��Ȯ�� ������ ���� ����:" -ForegroundColor Yellow
Write-Host "   1. ������ �������� ����" -ForegroundColor Gray
Write-Host "   2. �׽�Ʈ Ƚ�� ����: -TestCount 10" -ForegroundColor Gray
Write-Host "   3. �ٸ� �ð��뿡 ������" -ForegroundColor Gray
Write-Host "   4. �ٸ� ��Ʈ��ũ ȯ�濡�� ����" -ForegroundColor Gray

Write-Host ""
Write-Host "[COMPLETE] Cold Start �׽�Ʈ �Ϸ�!" -ForegroundColor Green