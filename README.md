## 링크
> S3: http://jys-new-bucket.s3-website-ap-southeast-2.amazonaws.com
> 
> CloudFront: https://d18gdmgx2pxnac.cloudfront.net

## 배포 아키텍처
![next](https://github.com/user-attachments/assets/51fb3968-2f9f-4d2b-a0f6-1e3435aadbc2)

# GitHub Actions 자동 배포 프로세스
### 자동 배포 조건
- **main 브랜치에 push**: 코드가 main 브랜치에 병합될 때 자동 실행
- **수동 실행**: GitHub Actions 탭에서 "Run workflow" 버튼으로 수동 실행 가능

```yaml
on:
  push:
    branches:
      - main
  workflow_dispatch:
```

---

## 📋 배포 프로세스 단계별 분석

### **1. 코드 체크아웃**
빌드 후 푸시하면 GitHub Actions에 변경사항 업로드

```yaml
- name: Checkout repository
  uses: actions/checkout@v4
```

---

### **2. 의존성 설치**
package-lock.json을 기준으로 프로젝트 의존성 설치

```yaml
- name: Install dependencies
  run: npm ci
```

**npm ci vs npm install 차이점:**
- `npm ci`: package-lock.json 기준으로 정확한 버전 설치 (CI/CD 환경 최적화)
- `npm install`: package.json 기준으로 유연한 버전 설치
- CI 환경에서는 `npm ci` 사용으로 일관성 보장

---

### **3. 프로젝트 빌드**
Next.js 프로젝트 빌드하여 배포 가능한 파일을 생성

`next.config.ts`의 `output: "export"` 설정 적용 `out/` 디렉토리에 배포 가능한 정적 파일 생성

```yaml
- name: Build
  run: npm run build
```

---
### 4. IAM 권한과 역할

#### **4-1. S3Actions**
| 권한 | 사용 시점 | 설명 |
|------|-----------|------|
| `s3:PutObject` | 파일 업로드 | `npm run build` 결과물을 S3에 업로드 |
| `s3:GetObject` | 파일 확인 | 업로드된 파일 검증 및 동기화 비교 |
| `s3:ListBucket` | 동기화 작업 | `aws s3 sync`에서 기존 파일과 비교 |
| `s3:DeleteObject` | 파일 정리 | `--delete` 옵션으로 불필요한 파일 제거 |
| `s3:GetBucketLocation` | 지역 확인 | S3 버킷의 AWS 리전 정보 확인 |
| `s3:ListAllMyBuckets` | 버킷 검색 | 접근 가능한 버킷 목록 확인 |

#### **4-2. CloudFrontActions 권한과 역할**
| 권한 | 사용 시점 | 설명 |
|------|-----------|------|
| `cloudfront:CreateInvalidation` | 배포 완료 후 | S3 파일 업데이트 후 CDN 캐시 강제 갱신 |
| `cloudfront:GetDistribution` | 무효화 실행 전 | 배포 상태 및 설정 정보 확인 |
| `cloudfront:ListDistributions` | 배포 ID 확인 | 접근 가능한 CloudFront 배포 목록 조회 |

#### **4-3. IAM ManageOwnAccessKeys 권한과 역할**
| 권한 | 목적 | 실무 활용 |
|------|------|-----------|
| `iam:CreateAccessKey` | 키 생성 | 새로운 배포 환경 설정 시 |
| `iam:DeleteAccessKey` | 키 삭제 | 보안 사고 시 긴급 차단 |
| `iam:GetAccessKeyLastUsed` | 사용 추적 | 보안 감사 및 모니터링 |
| `iam:GetUser` | 사용자 정보 | 계정 상태 및 권한 확인 |
| `iam:ListAccessKeys` | 키 관리 | 활성 키 목록 확인 |
| `iam:UpdateAccessKey` | 키 비활성화 | 임시 중단 시 사용 |

---

### **5. S3 버킷 동기화**
빌드된 정적 파일들을 AWS S3 버킷에 업로드하여 웹사이트 호스팅을 준비

```yaml
- name: Deploy to S3
  run: |
    aws s3 sync out/ s3://${{ secrets.S3_BUCKET_NAME }} --delete
```

**동작 과정:**
1. **파일 비교**: 로컬 `out/` 디렉토리와 S3 버킷 내용 비교
2. **새 파일 업로드**: 변경된 파일만 선별적으로 업로드
3. **불필요한 파일 삭제**: `--delete` 옵션으로 S3에만 있는 파일 정리

---

### 필수 Secrets 목록
| Secret 이름 | 설명 | 예시 값 |
|-------------|------|---------|
| `AWS_ACCESS_KEY_ID` | AWS IAM 액세스 키 | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM 시크릿 키 | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | AWS 리전 | `ap-southeast-2` |
| `S3_BUCKET_NAME` | S3 버킷 이름 | `my-website-bucket` |
| `CLOUDFRONT_DISTRIBUTION_ID` | CloudFront 배포 ID | `E1PA6795UKMFR9` |

### Secrets 설정 방법
1. GitHub 저장소 → Settings → Secrets and variables → Actions
2. "New repository secret" 클릭
3. 위 표의 각 항목을 이름과 값에 맞게 입력

---

---
## 테스트

#### 콜드 스타트 성능 측정
![network](https://github.com/user-attachments/assets/7590e8bf-d76e-45ca-a42a-2016d4152759)

CloudFront 의 Miss -> Hit 변화 과정
![CF.svg](README_SRC/CF.svg)

> #### PowerShell 테스트
> https://github.com/JYPPAP/4-1-PowerShellScript/blob/main/Cache-Flush-Performance-Test.ps1
> ![Performance-Test-01.png](README_SRC/Performance-Test-01.png)
> ![Performance-Test-02.png](README_SRC/Performance-Test-02.png)
> ![Performance-Test-03.png](README_SRC/Performance-Test-03.png)
> ![Performance-Test-04.png](README_SRC/Performance-Test-04.png)

#### 브라우저 테스트
##### S3 1회차 캐시X
> ![S3 1회차 캐시X html 시간.png](README_SRC/S3%201%ED%9A%8C%EC%B0%A8%20%EC%BA%90%EC%8B%9CX%20html%20%EC%8B%9C%EA%B0%84.png)
> ![S3 1회차 캐시X 하단 출력.png](README_SRC/S3%201%ED%9A%8C%EC%B0%A8%20%EC%BA%90%EC%8B%9CX%20%ED%95%98%EB%8B%A8%20%EC%B6%9C%EB%A0%A5.png)
##### S3 2회차 캐시X
> ![S3 2회차 캐시X html 시간.png](README_SRC/S3%202%ED%9A%8C%EC%B0%A8%20%EC%BA%90%EC%8B%9CX%20html%20%EC%8B%9C%EA%B0%84.png)
> ![S3 2회차 캐시X 하단 출력.png](README_SRC/S3%202%ED%9A%8C%EC%B0%A8%20%EC%BA%90%EC%8B%9CX%20%ED%95%98%EB%8B%A8%20%EC%B6%9C%EB%A0%A5.png)
##### S3 3회차 캐시O
> ![S3 3회차 캐시O html 시간.png](README_SRC/S3%203%ED%9A%8C%EC%B0%A8%20%EC%BA%90%EC%8B%9CO%20html%20%EC%8B%9C%EA%B0%84.png)
> ![S3 3회차 캐시O 하단 출력.png](README_SRC/S3%203%ED%9A%8C%EC%B0%A8%20%EC%BA%90%EC%8B%9CO%20%ED%95%98%EB%8B%A8%20%EC%B6%9C%EB%A0%A5.png)

##### CloudFront 1회차 캐시X
> ![CF 1회차 캐시X 하단 출력.png](README_SRC/CF%201%ED%9A%8C%EC%B0%A8%20%EC%BA%90%EC%8B%9CX%20%ED%95%98%EB%8B%A8%20%EC%B6%9C%EB%A0%A5.png)
> ![CF MISS2.png](README_SRC/CF%20MISS2.png)
##### CloudFront 2회차 캐시X
> ![CF 2회차 캐시X html 시간.png](README_SRC/CF%202%ED%9A%8C%EC%B0%A8%20%EC%BA%90%EC%8B%9CX%20html%20%EC%8B%9C%EA%B0%84.png)
> ![CF HIT2.png](README_SRC/CF%20HIT2.png)
##### CloudFront 3회차 캐시O
> ![CF 3회차 캐시O html 시간.png](README_SRC/CF%203%ED%9A%8C%EC%B0%A8%20%EC%BA%90%EC%8B%9CO%20html%20%EC%8B%9C%EA%B0%84.png)
> ![CF 3회차 캐시O 하단 출력.png](README_SRC/CF%203%ED%9A%8C%EC%B0%A8%20%EC%BA%90%EC%8B%9CO%20%ED%95%98%EB%8B%A8%20%EC%B6%9C%EB%A0%A5.png)

