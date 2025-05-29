# Cache-Flush-Performance-Test-Fixed.ps1
# URL 생성 오류 수정 버전

param(
    [string]$S3Url = "http://jys-new-bucket.s3-website-ap-southeast-2.amazonaws.com/",
    [string]$CloudFrontUrl = "https://d18gdmgx2pxnac.cloudfront.net/",
    [int]$TestCount = 3
)

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "     완전한 캐시 초기화 성능 테스트" -ForegroundColor Cyan  
Write-Host "===========================================" -ForegroundColor Cyan

# URL 유효성 검사 함수
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

# 디버깅 정보 출력
Write-Host "[DEBUG] URL 검증:" -ForegroundColor Yellow
Write-Host "S3 URL: '$S3Url'" -ForegroundColor Gray
Write-Host "CloudFront URL: '$CloudFrontUrl'" -ForegroundColor Gray
Write-Host "S3 URL 유효: $(Test-UrlValid $S3Url)" -ForegroundColor Gray
Write-Host "CloudFront URL 유효: $(Test-UrlValid $CloudFrontUrl)" -ForegroundColor Gray
Write-Host ""

# 캐시 초기화 함수
function Clear-AllCaches {
    Write-Host "[FLUSH] 모든 캐시 초기화 중..." -ForegroundColor Yellow
    
    try {
        # 1. DNS 캐시 초기화
        Write-Host "   DNS 캐시 초기화..." -ForegroundColor Gray
        ipconfig /flushdns | Out-Null
        
        # 2. 네트워크 연결 초기화 (관리자 권한 필요시)
        Write-Host "   네트워크 캐시 초기화..." -ForegroundColor Gray
        # netsh int ip reset | Out-Null  # 너무 강력한 명령어라 주석 처리
        
        # 3. 잠시 대기 (DNS 전파)
        Start-Sleep -Seconds 2
        
        Write-Host "   캐시 초기화 완료!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "   캐시 초기화 실패: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   관리자 권한으로 실행하세요" -ForegroundColor Yellow
        return $false
    }
}

# 강제 Cold Start 측정 함수 (수정됨)
function Measure-ColdStart {
    param(
        [string]$BaseUrl,
        [string]$ServiceName
    )
    
    # URL 유효성 먼저 검사
    if (-not (Test-UrlValid $BaseUrl)) {
        Write-Host "   오류: 잘못된 기본 URL - $BaseUrl" -ForegroundColor Red
        return @{
            Success = $false
            Error = "Invalid Base URL"
            TotalTimeMs = 0
        }
    }
    
    # 고유한 쿼리 파라미터로 캐시 우회
    $timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    $randomGuid = [System.Guid]::NewGuid().ToString()
    
    # URL 조합을 더 안전하게 처리
    if ($BaseUrl.EndsWith('/')) {
        $coldUrl = $BaseUrl + "?coldstart=$timestamp&random=$randomGuid"
    } else {
        $coldUrl = $BaseUrl + "/?coldstart=$timestamp&random=$randomGuid"
    }
    
    Write-Host "   Cold Start URL: $coldUrl" -ForegroundColor Gray
    
    # 생성된 URL 재검증
    if (-not (Test-UrlValid $coldUrl)) {
        Write-Host "   오류: 잘못된 생성 URL - $coldUrl" -ForegroundColor Red
        return @{
            Success = $false
            Error = "Invalid Generated URL"
            TotalTimeMs = 0
        }
    }
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # 모든 캐시 우회 헤더
        $headers = @{
            'Cache-Control' = 'no-cache, no-store, must-revalidate'
            'Pragma' = 'no-cache'
            'Expires' = '0'
        }
        
        $response = Invoke-WebRequest -Uri $coldUrl -Headers $headers -UseBasicParsing -TimeoutSec 30
        $stopwatch.Stop()
        
        # CloudFront 헤더 추출
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

# 진정한 Cold Start 비교 함수
function Test-TrueColdStart {
    param(
        [string]$Url,
        [string]$ServiceName,
        [string]$Color
    )
    
    Write-Host "[$ServiceName] 진정한 Cold Start 테스트" -ForegroundColor $Color
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "기본 URL: $Url" -ForegroundColor Gray
    
    $times = @()
    $cacheStatuses = @()
    
    for ($i = 1; $i -le $TestCount; $i++) {
        Write-Host "[$i/$TestCount] Cold Start 측정..." -ForegroundColor Yellow
        
        # 각 테스트마다 캐시 초기화 (첫 번째 제외)
        if ($i -gt 1) {
            Write-Host "   캐시 초기화 중..." -ForegroundColor Gray
            Clear-AllCaches | Out-Null
        }
        
        $result = Measure-ColdStart -BaseUrl $Url -ServiceName $ServiceName
        
        if ($result.Success) {
            $times += $result.TotalTimeMs
            $cacheStatuses += $result.XCache
            
            Write-Host "   총 시간: $($result.TotalTimeMs) ms" -ForegroundColor Green
            Write-Host "   파일 크기: $($result.ResponseSize) bytes" -ForegroundColor Gray
            
            if ($ServiceName -eq "CloudFront") {
                Write-Host "   캐시 상태: $($result.XCache)" -ForegroundColor $(if($result.XCache -like "*Hit*") { "Green" } else { "Red" })
                if ($result.Age -ne "") {
                    Write-Host "   캐시 나이: $($result.Age) 초" -ForegroundColor Gray
                }
                if ($result.Via -ne "") {
                    Write-Host "   Via: $($result.Via)" -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "   오류: $($result.Error)" -ForegroundColor Red
        }
        
        Write-Host ""
        
        # 테스트 간 충분한 대기
        if ($i -lt $TestCount) {
            Start-Sleep -Seconds 3
        }
    }
    
    if ($times.Count -gt 0) {
        $avg = ($times | Measure-Object -Average).Average
        $min = ($times | Measure-Object -Minimum).Minimum
        $max = ($times | Measure-Object -Maximum).Maximum
        
        Write-Host "[$ServiceName] 결과:" -ForegroundColor $Color
        Write-Host "   평균: $([math]::Round($avg, 2)) ms" -ForegroundColor Green
        Write-Host "   최소: $min ms" -ForegroundColor Gray
        Write-Host "   최대: $max ms" -ForegroundColor Gray
        
        if ($ServiceName -eq "CloudFront") {
            $missCount = ($cacheStatuses | Where-Object { $_ -like "*Miss*" }).Count
            $hitCount = ($cacheStatuses | Where-Object { $_ -like "*Hit*" }).Count
            Write-Host "   캐시 Miss: $missCount 회" -ForegroundColor Red
            Write-Host "   캐시 Hit: $hitCount 회" -ForegroundColor Green
        }
        
        return $avg
    } else {
        Write-Host "[$ServiceName] 측정 실패" -ForegroundColor Red
        return 0
    }
}

# 간단한 연결 테스트 먼저 실행
Write-Host "[CONNECT] 기본 연결 테스트:" -ForegroundColor Yellow
try {
    Write-Host "S3 연결 테스트..." -ForegroundColor Gray
    $s3Test = Invoke-WebRequest -Uri $S3Url -UseBasicParsing -TimeoutSec 5
    Write-Host "S3 연결 성공 (상태: $($s3Test.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "S3 연결 실패: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "스크립트를 종료합니다." -ForegroundColor Red
    exit 1
}

try {
    Write-Host "CloudFront 연결 테스트..." -ForegroundColor Gray
    $cfTest = Invoke-WebRequest -Uri $CloudFrontUrl -UseBasicParsing -TimeoutSec 5
    Write-Host "CloudFront 연결 성공 (상태: $($cfTest.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "CloudFront 연결 실패: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "스크립트를 종료합니다." -ForegroundColor Red
    exit 1
}

Write-Host ""

# 사전 캐시 초기화
Write-Host "[INIT] 초기 캐시 초기화..." -ForegroundColor Cyan
$flushResult = Clear-AllCaches

if (-not $flushResult) {
    Write-Host "[WARNING] 캐시 초기화에 실패했습니다. 관리자 권한으로 실행하면 더 정확한 결과를 얻을 수 있습니다." -ForegroundColor Yellow
    Write-Host ""
}

# S3 Cold Start 테스트
Write-Host ""
$s3Avg = Test-TrueColdStart -Url $S3Url -ServiceName "S3" -Color "Blue"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan

# CloudFront Cold Start 테스트  
$cfAvg = Test-TrueColdStart -Url $CloudFrontUrl -ServiceName "CloudFront" -Color "Red"

# 최종 비교
Write-Host ""
Write-Host "[FINAL] 최종 Cold Start 비교 결과" -ForegroundColor Magenta
Write-Host "===========================================" -ForegroundColor Cyan

if ($s3Avg -gt 0 -and $cfAvg -gt 0) {
    Write-Host "S3 Cold Start 평균: $([math]::Round($s3Avg, 2)) ms" -ForegroundColor Blue
    Write-Host "CloudFront Cold Start 평균: $([math]::Round($cfAvg, 2)) ms" -ForegroundColor Red
    
    $timeDiff = [math]::Abs($s3Avg - $cfAvg)
    Write-Host "시간 차이: $([math]::Round($timeDiff, 2)) ms" -ForegroundColor Yellow
    
    if ($s3Avg -gt $cfAvg) {
        $improvement = ($s3Avg - $cfAvg) / $s3Avg * 100
        Write-Host "WINNER: CloudFront가 $([math]::Round($improvement, 1))% 빠름!" -ForegroundColor Green
    } elseif ($cfAvg -gt $s3Avg) {
        $improvement = ($cfAvg - $s3Avg) / $cfAvg * 100
        Write-Host "WINNER: S3가 $([math]::Round($improvement, 1))% 빠름!" -ForegroundColor Green
    } else {
        Write-Host "RESULT: 거의 동일한 성능" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "[INFO] 분석:" -ForegroundColor Cyan
    if ($timeDiff -lt 50) {
        Write-Host "   차이가 50ms 미만으로 네트워크 지연 오차 범위입니다." -ForegroundColor Gray
        Write-Host "   더 많은 테스트가 필요할 수 있습니다." -ForegroundColor Gray
    }
} else {
    Write-Host "측정에 실패했습니다." -ForegroundColor Red
}

Write-Host ""
Write-Host "[TIP] 더 정확한 측정을 위한 제안:" -ForegroundColor Yellow
Write-Host "   1. 관리자 권한으로 실행" -ForegroundColor Gray
Write-Host "   2. 테스트 횟수 증가: -TestCount 10" -ForegroundColor Gray
Write-Host "   3. 다른 시간대에 재측정" -ForegroundColor Gray
Write-Host "   4. 다른 네트워크 환경에서 측정" -ForegroundColor Gray

Write-Host ""
Write-Host "[COMPLETE] Cold Start 테스트 완료!" -ForegroundColor Green